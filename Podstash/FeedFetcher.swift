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
    
    init(modelContext: ModelContext, settings: AppSettings, imageCacheManager: ImageCacheManager? = nil, downloadManager: DownloadManager? = nil) {
        self.modelContext = modelContext
        self.settings = settings
        self.imageCacheManager = imageCacheManager ?? .shared
        self.downloadManager = downloadManager
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
    
    // Not private: exercised directly by FeedFetcherTests with hand-built ParsedPodcast/
    // ParsedEpisode fixtures, bypassing the network fetch in fetchFeed(for:) above.
    @MainActor
    func updatePodcastAndEpisodes(
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
        
        // Match parsed episodes against what's already stored locally, preferring guid (the
        // RSS-spec stable identifier) over audioURL. Ad-supported feeds routinely rotate
        // tracking tokens in the enclosure URL, so audioURL alone isn't reliable - matching on
        // it exclusively caused already-played episodes to be recreated as "new" whenever their
        // URL moved. Episodes stored before guid tracking existed are backfilled here so future
        // refreshes match on guid too. Episode has no relationship to Podcast (see Models.swift),
        // so "what's already stored for this podcast" is a podcastID-scoped fetch, not
        // `podcast.episodes`.
        let podcastID = podcast.id
        let existingDescriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { $0.podcastID == podcastID }
        )
        let existingEpisodes = (try? modelContext.fetch(existingDescriptor)) ?? []

        var existingByGUID: [String: Episode] = [:]
        var existingByAudioURL: [String: Episode] = [:]
        for episode in existingEpisodes {
            if let guid = episode.guid {
                existingByGUID[guid] = episode
            }
            existingByAudioURL[episode.audioURL] = episode
        }

        // The newest publishDate this device has ever seen for this feed, captured before any
        // mutation below. Gates auto-download/auto-queue eligibility: an item at or before this
        // date never triggers auto-download even if it doesn't have a local Episode row yet
        // (e.g. retention cleanup deleted its old row, or a device is subscribing for the first
        // time) - this is what makes it safe to have no tombstone mechanism at all. A local
        // Episode row can still get recreated for it (harmless, metadata-only, local-only), it
        // just never resurrects into the queue or triggers a fresh download.
        let watermarkBeforeRefresh = podcast.newestKnownPublishDate ?? .distantPast

        // Guids/audioURLs staged into newEpisodeData during this same pass - checked alongside
        // existingByGUID/existingByAudioURL below so that a feed listing the same item twice
        // (a duplicate <item> block, a republish, a feed-generator bug - all things real feeds
        // do) doesn't create two Episode rows for it in a single refresh.
        var stagedGUIDs: Set<String> = []
        var stagedAudioURLs: Set<String> = []

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
            if let guid = parsedEpisode.guid, stagedGUIDs.contains(guid) {
                continue
            }
            if stagedAudioURLs.contains(parsedEpisode.audioURL) {
                continue
            }

            if let guid = parsedEpisode.guid {
                stagedGUIDs.insert(guid)
            }
            stagedAudioURLs.insert(parsedEpisode.audioURL)
            newEpisodeData.append(parsedEpisode)
        }

        // Create new episode objects
        var createdEpisodes: [Episode] = []
        for parsedEpisode in newEpisodeData {
            let episode = Episode(
                title: parsedEpisode.title,
                episodeDescription: parsedEpisode.description,
                audioURL: parsedEpisode.audioURL,
                guid: parsedEpisode.guid,
                duration: parsedEpisode.duration,
                publishDate: parsedEpisode.publishDate,
                artworkURL: parsedEpisode.artworkURL,
                podcastID: podcastID
            )

            modelContext.insert(episode)
            createdEpisodes.append(episode)
        }

        // Advance the watermark over every item this refresh saw, not just newly-created ones -
        // a feed that hasn't published anything new still needs the watermark to reflect the
        // newest item it currently lists.
        if let newestParsed = parsedEpisodes.map(\.publishDate).max() {
            podcast.newestKnownPublishDate = max(watermarkBeforeRefresh, newestParsed)
        }

        // Auto-download the most recent NEW episodes per the user's setting, gated to genuinely
        // new material (newer than the watermark) - not just "was created this refresh", since a
        // fresh Episode row can also get created for an old item whose previous row was deleted
        // by retention cleanup, and that shouldn't re-trigger a download.
        if settings.autoDownloadNewEpisodes, let downloadManager = downloadManager {
            let recentEpisodes = createdEpisodes
                .filter { $0.publishDate > watermarkBeforeRefresh }
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
    
    /// Fetch feeds for multiple podcasts one at a time to keep the UI responsive
    func fetchFeeds(for podcasts: [Podcast], progressHandler: ((String, Int, Int) -> Void)? = nil) async -> [Podcast: Result<Void, Error>] {
        var results: [Podcast: Result<Void, Error>] = [:]
        var updatedPodcasts: [Podcast] = []

        let total = podcasts.count
        var lastProgressUpdate = CFAbsoluteTimeGetCurrent()

        for (index, podcast) in podcasts.enumerated() {
            if Task.isCancelled { break }

            let result: Result<Void, Error>
            do {
                try await fetchFeed(for: podcast, shouldSave: false)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            // Throttle progress updates to reduce UI thrashing
            let completed = index + 1
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastProgressUpdate > 0.1 || completed == total {
                progressHandler?(podcast.title, completed, total)
                lastProgressUpdate = now
            }

            results[podcast] = result
            if case .success = result {
                updatedPodcasts.append(podcast)
            }
        }

        // ONE SINGLE SAVE AT THE END - no intermediate saves!
        if !Task.isCancelled {
            // Update all timestamps at once to trigger ONE UI update instead of 40
            let now = Date()
            for podcast in updatedPodcasts {
                podcast.lastUpdated = now
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
