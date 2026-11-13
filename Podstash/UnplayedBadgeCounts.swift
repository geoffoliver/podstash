//
//  UnplayedBadgeCounts.swift
//  Podstash
//

import Foundation
import SwiftData

/// The sidebar's per-podcast "unplayed" badge counts (see UnplayedEligibilityPolicy for what
/// counts). Pulled out of PodcastListView so the candidate-gathering fetch is testable against a
/// real ModelContext. Never call this from a View's `body` - see PodcastListView's
/// recomputeDownloadedUnplayedCounts for why it has to stay off the render path.
enum UnplayedBadgeCounts {
    /// Every episode that could possibly be eligible: everything downloaded, plus each podcast's
    /// non-downloaded episodes at or after that podcast's OWN eligibility threshold.
    ///
    /// One small fetch per podcast rather than one fetch bounded by the earliest threshold across
    /// all of them: a single long-dead feed (threshold years in the past) made that shared bound
    /// pull every other podcast's recent back-catalog into memory too - ~7,000 Episode objects
    /// and ~10 MB of descriptions per recompute in a real 38-podcast library, almost all of them
    /// thrown away by isEligible. Each per-podcast fetch here is served by Episode's
    /// (podcastID, publishDate) index and typically returns zero to a handful of rows.
    static func candidateEpisodes(for podcasts: [Podcast], in context: ModelContext) -> [Episode] {
        let downloadedDescriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.isDownloaded })
        var candidateEpisodes = (try? context.fetch(downloadedDescriptor)) ?? []

        for podcast in podcasts {
            guard let threshold = podcast.mostRecentlyPlayedDate ?? podcast.newestKnownPublishDate else { continue }
            let podcastID = podcast.id
            let descriptor = FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> {
                    $0.podcastID == podcastID && $0.publishDate >= threshold && !$0.isDownloaded
                }
            )
            if let recent = try? context.fetch(descriptor) {
                candidateEpisodes.append(contentsOf: recent)
            }
        }
        return candidateEpisodes
    }

    static func counts(for podcasts: [Podcast], in context: ModelContext) -> [UUID: Int] {
        let candidateEpisodes = candidateEpisodes(for: podcasts, in: context)
        guard !candidateEpisodes.isEmpty else { return [:] }

        // An episode can appear in both the downloaded fetch and the recency fetch above - dedupe
        // by episodeKey before joining state, same helper QueueView.queuedEpisodes uses for the
        // same reason.
        let deduped = PlaybackRecordStore.firstByKey(candidateEpisodes).values
        let states = PlaybackRecordStore.states(forKeys: Set(deduped.map(\.episodeKey)), in: context)
        let podcastsByID = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.id, $0) })

        var counts: [UUID: Int] = [:]
        for episode in deduped {
            let podcast = podcastsByID[episode.podcastID]
            let eligible = UnplayedEligibilityPolicy.isEligible(
                isDownloaded: episode.isDownloaded,
                isPlayed: states[episode.episodeKey]?.isPlayed ?? false,
                publishDate: episode.publishDate,
                mostRecentlyPlayedDate: podcast?.mostRecentlyPlayedDate,
                newestKnownPublishDate: podcast?.newestKnownPublishDate
            )
            if eligible {
                counts[episode.podcastID, default: 0] += 1
            }
        }
        return counts
    }
}
