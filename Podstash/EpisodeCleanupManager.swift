//
//  EpisodeCleanupManager.swift
//  Podstash
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

    /// Reclaims disk space from downloaded audio per the user's retention policy. Never deletes
    /// an Episode's local metadata row - Episode is cheap, local-only metadata now (see
    /// Models.swift), not a large synced record, so there's no storage/sync reason to make the
    /// app forget an episode exists just because it's been played or has aged out. Only the
    /// actual disk-space cost (downloaded audio) is reclaimed, which is what these policies were
    /// really about; "All" tabs always show every episode the subscribed feed currently lists.
    func cleanupEpisodes() {
        let policy = settings.episodeRetentionPolicyEnum

        switch policy {
        case .all:
            // Keep every download, but check for auto-reclaiming played ones
            if settings.autoDeletePlayedEpisodes {
                reclaimOldPlayedDownloads()
            }

        case .unplayedOnly:
            // Reclaim every played episode's download
            reclaimPlayedDownloads()

        case .mostRecent:
            // Keep downloads for only the most recent X episodes per podcast
            reclaimDownloadsBeyondMostRecent(count: settings.episodeRetentionCount)
        }

        try? modelContext.save()
    }

    /// Downloaded episodes plus their played/date state, per the synced PlaybackRecord store -
    /// the local Episode row's played/date state doesn't exist anymore (see Models.swift), so
    /// retention always starts here rather than filtering Episode directly. Scoped to just the
    /// (usually single-digit-to-tens) downloaded episodes' keys via
    /// PlaybackRecordStore.states(forKeys:in:) rather than fetching every played PlaybackRecord -
    /// that table is never pruned and can reach tens of thousands of rows over time.
    private func downloadedEpisodeStates() -> (episodes: [Episode], states: [String: EpisodeState]) {
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.isDownloaded })
        let episodes = (try? modelContext.fetch(descriptor)) ?? []
        let keys = Set(episodes.map(\.episodeKey))
        let states = PlaybackRecordStore.states(forKeys: keys, in: modelContext)
        return (episodes, states)
    }

    private func reclaimPlayedDownloads() {
        let (episodes, states) = downloadedEpisodeStates()
        let playedEpisodes = episodes.filter { states[$0.episodeKey]?.isPlayed ?? false }
        guard !playedEpisodes.isEmpty else { return }

        for episode in playedEpisodes {
            deleteDownloadedFileIfNeeded(for: episode)
        }
    }

    private func reclaimOldPlayedDownloads() {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -settings.autoDeleteAfterDays,
            to: Date()
        ) ?? Date()

        let (episodes, states) = downloadedEpisodeStates()
        let oldPlayedEpisodes = episodes.filter { episode in
            guard let state = states[episode.episodeKey], state.isPlayed else { return false }
            return (state.lastPlayedDate ?? .distantPast) < cutoffDate
        }
        guard !oldPlayedEpisodes.isEmpty else { return }

        for episode in oldPlayedEpisodes {
            deleteDownloadedFileIfNeeded(for: episode)
        }
    }

    private func reclaimDownloadsBeyondMostRecent(count: Int) {
        let (_, states) = downloadedEpisodeStates()

        let podcastDescriptor = FetchDescriptor<Podcast>()
        guard let podcasts = try? modelContext.fetch(podcastDescriptor) else { return }

        for podcast in podcasts {
            let podcastID = podcast.id
            let episodeDescriptor = FetchDescriptor<Episode>(
                predicate: #Predicate { $0.podcastID == podcastID }
            )
            guard let episodes = try? modelContext.fetch(episodeDescriptor) else { continue }

            // Sort episodes by publish date (newest first)
            let sortedEpisodes = episodes.sorted { $0.publishDate > $1.publishDate }

            // Reclaim downloads beyond the most recent 'count' episodes. Only played ones are
            // touched - unplayed downloads are never auto-deleted, matching the other retention
            // policies (see AppSettings.episodeRetentionPolicy).
            let episodesToReclaim = Array(sortedEpisodes.dropFirst(count))
                .filter { $0.isDownloaded && (states[$0.episodeKey]?.isPlayed ?? false) }

            for episode in episodesToReclaim {
                deleteDownloadedFileIfNeeded(for: episode)
            }
        }
    }

    /// Removes a downloaded episode's audio file from disk, if present, and clears the
    /// isDownloaded/downloadedFilename flags so the (surviving) Episode row accurately reflects
    /// that the file is gone.
    private func deleteDownloadedFileIfNeeded(for episode: Episode) {
        guard episode.isDownloaded, let filename = episode.downloadedFilename else { return }
        try? FileManager.default.removeItem(at: DownloadManager.localFileURL(forStoredFilename: filename))
        episode.isDownloaded = false
        episode.downloadedFilename = nil
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
