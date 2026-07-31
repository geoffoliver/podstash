//
//  FeedFetcher.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftData

enum FeedFetchError: Error {
    case invalidURL
    case networkError(Error)
    case parsingFailed
    case noAudioContent
}

class FeedFetcher {
    let modelContext: ModelContext
    let settings: AppSettings
    let imageCacheManager: ImageCacheManager
    var downloadManager: DownloadManager?
    
    init(modelContext: ModelContext, settings: AppSettings, imageCacheManager: ImageCacheManager = .shared, downloadManager: DownloadManager? = nil) {
        self.modelContext = modelContext
        self.settings = settings
        self.imageCacheManager = imageCacheManager
        self.downloadManager = downloadManager
    }
    
    /// Determine optimal concurrency based on system capabilities
    private var maxConcurrentFetches: Int {
        let processorCount = ProcessInfo.processInfo.processorCount
        
        // Use 2-6 concurrent tasks based on CPU cores
        // More cores = more concurrent tasks, but cap it to avoid overwhelming the network
        switch processorCount {
        case 1...2:
            return 2  // Low-end devices
        case 3...4:
            return 3  // Mid-range devices
        case 5...8:
            return 4  // High-end devices
        default:
            return 6  // Very powerful devices (Mac, iPad Pro)
        }
    }
    
    /// Fetch and parse a single podcast feed, updating the podcast and adding episodes
    @MainActor
    func fetchFeed(for podcast: Podcast) async throws {
        // Clean and validate URL
        let cleanURL = podcast.feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanURL), 
              url.scheme == "http" || url.scheme == "https" else {
            throw FeedFetchError.invalidURL
        }
        
        // Capture what we need from the podcast
        let feedURL = url
        let existingAudioURLs = Set(podcast.episodes.map { $0.audioURL })
        let podcastID = podcast.persistentModelID
        
        // Do all the heavy lifting off the main actor
        let (parsedPodcast, newEpisodeData) = try await Task.detached { [modelContext, existingAudioURLs] in
            // Download feed data
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            
            // Parse feed
            let parser = RSSFeedParser()
            guard let parsedPodcast = parser.parse(data: data) else {
                throw FeedFetchError.parsingFailed
            }
            
            // Sort episodes by publish date (most recent first)
            let sortedEpisodes = parsedPodcast.episodes.sorted { $0.publishDate > $1.publishDate }
            
            // Identify new episodes
            let newEpisodeData = sortedEpisodes.filter { !existingAudioURLs.contains($0.audioURL) }
            
            return (parsedPodcast, newEpisodeData)
        }.value
        
        // Quick main actor update
        await updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: parsedPodcast,
            newEpisodeData: newEpisodeData
        )
        
        // Cache artwork in background
        Task.detached { [imageCacheManager] in
            await imageCacheManager.cacheArtwork(for: podcast)
        }
    }
    
    @MainActor
    private func updatePodcastAndEpisodes(
        podcast: Podcast,
        parsedPodcast: ParsedPodcast,
        newEpisodeData: [ParsedEpisode]
    ) async {
        // Update podcast metadata
        if podcast.podcastDescription == nil || podcast.podcastDescription?.isEmpty == true {
            podcast.podcastDescription = parsedPodcast.description
        }
        
        if podcast.artworkURL == nil {
            podcast.artworkURL = parsedPodcast.artworkURL
        }
        
        if podcast.author == nil {
            podcast.author = parsedPodcast.author
        }
        
        if podcast.websiteURL == nil {
            podcast.websiteURL = parsedPodcast.websiteURL
        }
        
        podcast.lastUpdated = Date()
        
        var newEpisodes: [Episode] = []
        
        // Create new episode objects
        for parsedEpisode in newEpisodeData {
            let episode = Episode(
                title: parsedEpisode.title,
                episodeDescription: parsedEpisode.description,
                audioURL: parsedEpisode.audioURL,
                duration: parsedEpisode.duration,
                publishDate: parsedEpisode.publishDate,
                artworkURL: parsedEpisode.artworkURL
            )
            
            episode.podcast = podcast
            modelContext.insert(episode)
            newEpisodes.append(episode)
        }
        
        try? modelContext.save()
        
        // Auto-download new episodes if enabled
        print("📥 Auto-download settings: enabled=\(settings.autoDownloadNewEpisodes), downloadManager=\(downloadManager != nil), newEpisodes=\(newEpisodes.count)")
        if settings.autoDownloadNewEpisodes, let downloadManager = downloadManager {
            let episodesToAutoDownload = newEpisodes.prefix(settings.maxEpisodesToDownload)
            print("📥 Starting auto-download for \(episodesToAutoDownload.count) of \(newEpisodes.count) new episode(s)")
            for episode in episodesToAutoDownload {
                print("📥 Downloading: \(episode.title)")
                downloadManager.downloadEpisode(episode)
            }
        }
    }
    
    /// Fetch feeds for multiple podcasts with concurrent processing
    func fetchFeeds(for podcasts: [Podcast], progressHandler: ((String, Int, Int) -> Void)? = nil) async -> [Podcast: Result<Void, Error>] {
        var results: [Podcast: Result<Void, Error>] = [:]
        let resultsLock = NSLock()
        
        // Process podcasts concurrently with a limit
        await withTaskGroup(of: (Podcast, Result<Void, Error>).self) { group in
            var currentIndex = 0
            let total = podcasts.count
            
            // Start initial batch of tasks
            for podcast in podcasts.prefix(maxConcurrentFetches) {
                group.addTask { [weak self] in
                    guard let self = self else {
                        return (podcast, .failure(FeedFetchError.parsingFailed))
                    }
                    
                    let result: Result<Void, Error>
                    do {
                        try await self.fetchFeed(for: podcast)
                        result = .success(())
                    } catch {
                        result = .failure(error)
                    }
                    
                    return (podcast, result)
                }
                currentIndex += 1
            }
            
            var completed = 0
            
            // As tasks complete, add new ones
            for await (podcast, result) in group {
                // Update progress on main actor
                await MainActor.run {
                    completed += 1
                    progressHandler?(podcast.title, completed, total)
                }
                
                // Store result
                resultsLock.lock()
                results[podcast] = result
                resultsLock.unlock()
                
                // Add next task if available
                if currentIndex < podcasts.count {
                    let nextPodcast = podcasts[currentIndex]
                    currentIndex += 1
                    
                    group.addTask { [weak self] in
                        guard let self = self else {
                            return (nextPodcast, .failure(FeedFetchError.parsingFailed))
                        }
                        
                        let result: Result<Void, Error>
                        do {
                            try await self.fetchFeed(for: nextPodcast)
                            result = .success(())
                        } catch {
                            result = .failure(error)
                        }
                        
                        return (nextPodcast, result)
                    }
                }
            }
        }
        
        return results
    }
    
    /// Fetch all subscribed podcast feeds
    @MainActor
    func fetchAllFeeds(progressHandler: ((String, Int, Int) -> Void)? = nil) async -> [Podcast: Result<Void, Error>] {
        let descriptor = FetchDescriptor<Podcast>(sortBy: [SortDescriptor(\.title)])
        let podcasts = (try? modelContext.fetch(descriptor)) ?? []
        
        return await fetchFeeds(for: podcasts, progressHandler: progressHandler)
    }
}
