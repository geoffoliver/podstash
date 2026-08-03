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
        // Process feeds one at a time to keep UI responsive
        return 1
    }
    
    /// Fetch and parse a single podcast feed, updating the podcast and adding episodes
    func fetchFeed(for podcast: Podcast, shouldSave: Bool = true) async throws {
        // Capture podcast data on main actor
        let feedURL: URL? = await MainActor.run {
            let cleanURL = podcast.feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: cleanURL)
        }

        guard let feedURL = feedURL,
              feedURL.scheme == "http" || feedURL.scheme == "https" else {
            throw FeedFetchError.invalidURL
        }

        // Do ALL the heavy work OFF the main thread using Task.detached
        let parsedData: (ParsedPodcast, [ParsedEpisode]) = try await Task.detached {
            // Check for cancellation
            try Task.checkCancellation()

            // Download feed data
            let (data, _) = try await URLSession.shared.data(from: feedURL)

            try Task.checkCancellation()

            // Parse feed
            let parser = RSSFeedParser()
            guard let parsedPodcast = parser.parse(data: data) else {
                throw FeedFetchError.parsingFailed
            }

            try Task.checkCancellation()

            // Sort episodes by publish date
            let sortedEpisodes = parsedPodcast.episodes.sorted { $0.publishDate > $1.publishDate }

            return (parsedPodcast, sortedEpisodes)
        }.value

        // Matching parsed episodes against what's already stored happens on the main actor,
        // where the live Episode objects live.
        await updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: parsedData.0,
            parsedEpisodes: parsedData.1,
            shouldSave: shouldSave
        )
    }
    
    @MainActor
    private func updatePodcastAndEpisodes(
        podcast: Podcast,
        parsedPodcast: ParsedPodcast,
        parsedEpisodes: [ParsedEpisode],
        updateTimestamp: Bool = true,
        shouldSave: Bool = false
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
        
        // Only update timestamp if requested (skip during batch to avoid UI thrashing)
        if updateTimestamp {
            podcast.lastUpdated = Date()
        }
        
        // Match parsed episodes against what's already stored, preferring guid (the RSS-spec
        // stable identifier) over audioURL. Ad-supported feeds routinely rotate tracking tokens
        // in the enclosure URL, so audioURL alone isn't reliable - matching on it exclusively
        // caused already-played episodes to be recreated as "new" (unplayed, requeued) whenever
        // their URL moved. Episodes stored before guid tracking existed are backfilled here so
        // future refreshes match on guid too.
        var existingByGUID: [String: Episode] = [:]
        var existingByAudioURL: [String: Episode] = [:]
        for episode in podcast.episodes {
            if let guid = episode.guid {
                existingByGUID[guid] = episode
            }
            existingByAudioURL[episode.audioURL] = episode
        }

        var newEpisodeData: [ParsedEpisode] = []
        for parsedEpisode in parsedEpisodes {
            if let guid = parsedEpisode.guid, existingByGUID[guid] != nil {
                continue
            }
            if let existing = existingByAudioURL[parsedEpisode.audioURL] {
                if existing.guid == nil, let guid = parsedEpisode.guid {
                    existing.guid = guid
                }
                continue
            }
            newEpisodeData.append(parsedEpisode)
        }

        // Create new episode objects
        for parsedEpisode in newEpisodeData {
            let episode = Episode(
                title: parsedEpisode.title,
                episodeDescription: parsedEpisode.description,
                audioURL: parsedEpisode.audioURL,
                guid: parsedEpisode.guid,
                duration: parsedEpisode.duration,
                publishDate: parsedEpisode.publishDate,
                artworkURL: parsedEpisode.artworkURL
            )

            episode.podcast = podcast
            modelContext.insert(episode)
        }
        
        // Auto-download the most recent episodes per the user's setting
        if settings.autoDownloadNewEpisodes, let downloadManager = downloadManager {
            let recentEpisodes = podcast.episodes
                .sorted { $0.publishDate > $1.publishDate }
                .prefix(settings.maxEpisodesToDownload)

            for episode in recentEpisodes
            where !episode.isDownloaded && !downloadManager.isDownloading(episode) {
                downloadManager.downloadEpisode(episode)
            }
        }

        // Save if requested
        if shouldSave {
            try? modelContext.save()
        }

        // Yield to let other tasks run and keep UI responsive
        await Task.yield()
    }
    
    /// Fetch feeds for multiple podcasts with concurrent processing
    func fetchFeeds(for podcasts: [Podcast], progressHandler: ((String, Int, Int) -> Void)? = nil) async -> [Podcast: Result<Void, Error>] {
        var results: [Podcast: Result<Void, Error>] = [:]
        let resultsLock = NSLock()
        
        // Track podcasts that were successfully updated
        var updatedPodcasts: [Podcast] = []
        let podcastsLock = NSLock()
        
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
                    
                    // Check for cancellation before starting
                    if Task.isCancelled {
                        return (podcast, .failure(CancellationError()))
                    }
                    
                    let result: Result<Void, Error>
                    do {
                        try await self.fetchFeed(for: podcast, shouldSave: false)
                        result = .success(())
                    } catch is CancellationError {
                        return (podcast, .failure(CancellationError()))
                    } catch {
                        result = .failure(error)
                    }
                    
                    return (podcast, result)
                }
                currentIndex += 1
            }
            
            var completed = 0
            var lastProgressUpdate = CFAbsoluteTimeGetCurrent()
            
            // As tasks complete, add new ones
            for await (podcast, result) in group {
                // Check for cancellation
                if Task.isCancelled {
                    break
                }
                
                // Throttle progress updates to reduce UI thrashing
                completed += 1
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastProgressUpdate > 0.1 || completed == total {
                    await MainActor.run {
                        progressHandler?(podcast.title, completed, total)
                    }
                    lastProgressUpdate = now
                }
                
                // Store result
                resultsLock.lock()
                results[podcast] = result
                resultsLock.unlock()
                
                // Track successfully updated podcasts
                if case .success = result {
                    podcastsLock.lock()
                    updatedPodcasts.append(podcast)
                    podcastsLock.unlock()
                }
                
                // Add next task if available and not cancelled
                if currentIndex < podcasts.count && !Task.isCancelled {
                    let nextPodcast = podcasts[currentIndex]
                    currentIndex += 1
                    
                    group.addTask { [weak self] in
                        guard let self = self else {
                            return (nextPodcast, .failure(FeedFetchError.parsingFailed))
                        }
                        
                        // Check for cancellation before starting
                        if Task.isCancelled {
                            return (nextPodcast, .failure(CancellationError()))
                        }
                        
                        let result: Result<Void, Error>
                        do {
                            try await self.fetchFeed(for: nextPodcast, shouldSave: false)
                            result = .success(())
                        } catch is CancellationError {
                            return (nextPodcast, .failure(CancellationError()))
                        } catch {
                            result = .failure(error)
                        }
                        
                        return (nextPodcast, result)
                    }
                }
            }
        }
        
        // ONE SINGLE SAVE AT THE END - no intermediate saves!
        if !Task.isCancelled {
            // Update all timestamps at once to trigger ONE UI update instead of 40
            await MainActor.run {
                let now = Date()
                for podcast in updatedPodcasts {
                    podcast.lastUpdated = now
                }
            }
            
            await performFinalSave()
        }
        
        return results
    }
    
    /// Perform the final save operation on the main actor
    @MainActor
    private func performFinalSave() async {
        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }
    
    /// Fetch all subscribed podcast feeds
    @MainActor
    func fetchAllFeeds(progressHandler: ((String, Int, Int) -> Void)? = nil) async -> [Podcast: Result<Void, Error>] {
        let descriptor = FetchDescriptor<Podcast>(sortBy: [SortDescriptor(\.title)])
        let podcasts = (try? modelContext.fetch(descriptor)) ?? []
        
        return await fetchFeeds(for: podcasts, progressHandler: progressHandler)
    }
}
