//
//  EpisodeCleanupManager.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftData

@MainActor
class EpisodeCleanupManager {
    private let modelContext: ModelContext
    private let settings: AppSettings
    
    init(modelContext: ModelContext, settings: AppSettings) {
        self.modelContext = modelContext
        self.settings = settings
    }
    
    /// Clean up episodes based on retention policy
    func cleanupEpisodes() {
        let policy = settings.episodeRetentionPolicyEnum
        
        switch policy {
        case .all:
            // Keep everything, but check for auto-delete played episodes
            if settings.autoDeletePlayedEpisodes {
                deleteOldPlayedEpisodes()
            }
            
        case .unplayedOnly:
            // Delete all played episodes
            deletePlayedEpisodes()
            
        case .mostRecent:
            // Keep only the most recent X episodes per podcast
            keepMostRecentEpisodes(count: settings.episodeRetentionCount)
        }
        
        try? modelContext.save()
    }
    
    private func deletePlayedEpisodes() {
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.isPlayed
            }
        )

        guard let episodes = try? modelContext.fetch(descriptor) else { return }

        for episode in episodes {
            deleteDownloadedFileIfNeeded(for: episode)
            recordTombstone(for: episode)
            modelContext.delete(episode)
        }
    }

    private func deleteOldPlayedEpisodes() {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -settings.autoDeleteAfterDays,
            to: Date()
        ) ?? Date()
        
        // Fetch all played episodes
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.isPlayed
            }
        )
        
        guard let episodes = try? modelContext.fetch(descriptor) else { return }
        
        // Filter in Swift instead of predicate (nil coalescing doesn't work in predicates)
        let oldEpisodes = episodes.filter { episode in
            let playedDate = episode.lastPlayedDate ?? Date.distantPast
            return playedDate < cutoffDate
        }
        
        for episode in oldEpisodes {
            deleteDownloadedFileIfNeeded(for: episode)
            recordTombstone(for: episode)
            modelContext.delete(episode)
        }
    }

    private func keepMostRecentEpisodes(count: Int) {
        // Get all podcasts
        let podcastDescriptor = FetchDescriptor<Podcast>()
        guard let podcasts = try? modelContext.fetch(podcastDescriptor) else { return }
        
        for podcast in podcasts {
            // Sort episodes by publish date (newest first)
            let sortedEpisodes = podcast.episodes.sorted { $0.publishDate > $1.publishDate }
            
            // Keep the first 'count' episodes, delete the rest. Only played episodes are
            // removed here - unplayed ones are never auto-deleted, matching the other
            // retention policies (see AppSettings.episodeRetentionPolicy).
            let episodesToDelete = Array(sortedEpisodes.dropFirst(count)).filter { $0.isPlayed }

            for episode in episodesToDelete {
                deleteDownloadedFileIfNeeded(for: episode)
                recordTombstone(for: episode)
                modelContext.delete(episode)
            }
        }
    }

    /// Collapses Episode rows that refer to the same feed item (matched by guid, falling back
    /// to audioURL - same preference FeedFetcher uses) into one. Duplicates happen because
    /// CloudKit sync is asynchronous: FeedFetcher only ever sees *this device's* currently-synced
    /// state, so if two devices each refresh the same feed before either's newly-created Episode
    /// row has synced to the other, both independently create their own row for the same item.
    /// Sorting by id (rather than local fetch/insertion order) before picking which row survives
    /// keeps the choice deterministic across devices, so independent runs of this pass tend to
    /// converge on the same survivor instead of leapfrogging each other.
    func deduplicateEpisodes() {
        let podcastDescriptor = FetchDescriptor<Podcast>()
        guard let podcasts = try? modelContext.fetch(podcastDescriptor) else { return }

        for podcast in podcasts {
            var survivorByKey: [String: Episode] = [:]

            for episode in podcast.episodes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let key = episode.guid ?? episode.audioURL
                guard !key.isEmpty else { continue }

                guard let survivor = survivorByKey[key] else {
                    survivorByKey[key] = episode
                    continue
                }

                merge(episode, into: survivor)
            }
        }

        try? modelContext.save()
    }

    /// Folds `duplicate`'s playback/download/queue state into `survivor`, then deletes
    /// `duplicate` (and any file it downloaded independently, since that copy is now redundant).
    private func merge(_ duplicate: Episode, into survivor: Episode) {
        let duplicateLastPlayed = duplicate.lastPlayedDate ?? .distantPast
        let survivorLastPlayed = survivor.lastPlayedDate ?? .distantPast
        if duplicate.isPlayed && (!survivor.isPlayed || duplicateLastPlayed > survivorLastPlayed) {
            survivor.isPlayed = true
            survivor.playbackPosition = duplicate.playbackPosition
            survivor.lastPlayedDate = duplicate.lastPlayedDate
        } else if !survivor.isPlayed {
            survivor.playbackPosition = max(survivor.playbackPosition, duplicate.playbackPosition)
        }

        if survivor.guid == nil {
            survivor.guid = duplicate.guid
        }

        if survivor.queuePosition == nil {
            survivor.queuePosition = duplicate.queuePosition
        }

        if duplicate.isDownloaded {
            if survivor.isDownloaded {
                // Both copies were downloaded independently - the duplicate's is redundant.
                deleteDownloadedFileIfNeeded(for: duplicate)
            } else {
                // `downloadedFilename` is just a stored name resolved against this device's
                // Downloads folder, so adopting the duplicate's is fine even though it embeds
                // the duplicate's (now-discarded) id rather than the survivor's.
                survivor.isDownloaded = true
                survivor.downloadedFilename = duplicate.downloadedFilename
            }
        }

        modelContext.delete(duplicate)
    }

    /// Removes a downloaded episode's audio file from disk, if present, before its `Episode`
    /// record is deleted - otherwise the file is orphaned (still on disk, but no longer
    /// reachable or counted since the record that tracked it is gone).
    private func deleteDownloadedFileIfNeeded(for episode: Episode) {
        guard episode.isDownloaded, let filename = episode.downloadedFilename else { return }
        try? FileManager.default.removeItem(at: DownloadManager.localFileURL(forStoredFilename: filename))
    }

    /// Leaves a marker behind so FeedFetcher recognizes this episode as already-seen (and
    /// already-played) even after this row is gone, instead of recreating it as new/unplayed
    /// on the next refresh. See DeletedEpisodeMarker's doc comment in Models.swift.
    private func recordTombstone(for episode: Episode) {
        guard let podcastID = episode.podcast?.id else { return }
        let marker = DeletedEpisodeMarker(
            podcastID: podcastID,
            guid: episode.guid,
            audioURL: episode.audioURL
        )
        modelContext.insert(marker)
    }

    /// Get storage usage information
    func getStorageInfo() -> (episodeCount: Int, downloadedCount: Int, estimatedSize: String) {
        let descriptor = FetchDescriptor<Episode>()
        guard let episodes = try? modelContext.fetch(descriptor) else {
            return (0, 0, "0 MB")
        }
        
        let downloadedCount = episodes.filter { $0.isDownloaded }.count
        
        // Rough estimate: 1 MB per minute of audio at medium quality
        let totalMinutes = episodes.reduce(0.0) { result, episode in
            if episode.isDownloaded, let duration = episode.duration {
                return result + (duration / 60.0)
            }
            return result
        }
        
        let estimatedMB = Int(totalMinutes)
        let sizeString: String
        if estimatedMB > 1024 {
            sizeString = String(format: "%.1f GB", Double(estimatedMB) / 1024.0)
        } else {
            sizeString = "\(estimatedMB) MB"
        }
        
        return (episodes.count, downloadedCount, sizeString)
    }
}
