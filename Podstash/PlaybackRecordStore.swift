//
//  PlaybackRecordStore.swift
//  Podstash
//

import Foundation
import SwiftData

/// The queue/played/position state for one episode, resolved from its PlaybackRecord if one
/// exists, or defaults if it doesn't (an episode nobody has ever played/queued has no
/// PlaybackRecord row - see PlaybackRecordStore.recordForMutation).
struct EpisodeState: Equatable {
    var isPlayed = false
    var playbackPosition: TimeInterval = 0
    var lastPlayedDate: Date?
    var queuePosition: Int?

    init() {}

    init(record: PlaybackRecord) {
        isPlayed = record.isPlayed
        playbackPosition = record.playbackPosition
        lastPlayedDate = record.lastPlayedDate
        queuePosition = record.queuePosition
    }
}

/// Pairs a local Episode (RSS-derived metadata) with its synced EpisodeState (queue/played/
/// position) for display. This is the join every list/detail view works with instead of reading
/// isPlayed/playbackPosition/queuePosition directly off Episode.
struct EpisodeDisplay: Identifiable, Equatable {
    let episode: Episode
    var state: EpisodeState
    var id: UUID { episode.id }
}

@MainActor
enum PlaybackRecordStore {
    /// Read path, batched: one predicate fetch scoped to exactly the keys needed (never all
    /// PlaybackRecord rows). Keys with no matching record are simply absent from the result -
    /// callers should treat a missing key as `EpisodeState()` (all defaults).
    static func states(forKeys keys: Set<String>, in context: ModelContext) -> [String: EpisodeState] {
        guard !keys.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<PlaybackRecord>(
            predicate: #Predicate { keys.contains($0.episodeKey) }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: records.map { ($0.episodeKey, EpisodeState(record: $0)) })
    }

    /// Joins a batch of Episodes to their EpisodeState in one shot, for building [EpisodeDisplay].
    static func display(for episodes: [Episode], in context: ModelContext) -> [EpisodeDisplay] {
        let keys = Set(episodes.map(\.episodeKey))
        let states = states(forKeys: keys, in: context)
        return episodes.map { EpisodeDisplay(episode: $0, state: states[$0.episodeKey] ?? EpisodeState()) }
    }

    /// Read path for a single episode - convenience wrapper over `states(forKeys:in:)`.
    static func state(for episode: Episode, in context: ModelContext) -> EpisodeState {
        states(forKeys: [episode.episodeKey], in: context)[episode.episodeKey] ?? EpisodeState()
    }

    /// Write path: the ONLY place a PlaybackRecord gets created. Every mutation site (mark
    /// played, queue, save progress) should fetch-or-create through here rather than inserting
    /// a PlaybackRecord directly, so there's a single source of truth for "does one already
    /// exist for this key."
    static func recordForMutation(episodeKey: String, in context: ModelContext) -> PlaybackRecord {
        let descriptor = FetchDescriptor<PlaybackRecord>(
            predicate: #Predicate { $0.episodeKey == episodeKey }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let record = PlaybackRecord(episodeKey: episodeKey)
        context.insert(record)
        return record
    }

    /// Periodic dedup for the CloudKit-uniqueness gap: SwiftData doesn't support
    /// @Attribute(.unique) under CloudKit mirroring, so two devices each first-touching the same
    /// episode before either's row syncs can produce two PlaybackRecord rows for one episodeKey.
    /// Same merge preference as the old EpisodeCleanupManager.merge: prefer isPlayed=true; prefer
    /// the more recent lastPlayedDate; prefer the larger playbackPosition when neither is played;
    /// prefer having a queuePosition over not having one.
    static func deduplicate(in context: ModelContext) {
        guard let allRecords = try? context.fetch(FetchDescriptor<PlaybackRecord>()) else { return }

        var survivorByKey: [String: PlaybackRecord] = [:]

        for record in allRecords.sorted(by: { $0.episodeKey < $1.episodeKey }) {
            guard !record.episodeKey.isEmpty else { continue }

            guard let survivor = survivorByKey[record.episodeKey] else {
                survivorByKey[record.episodeKey] = record
                continue
            }

            merge(record, into: survivor)
            context.delete(record)
        }

        try? context.save()
    }

    private static func merge(_ duplicate: PlaybackRecord, into survivor: PlaybackRecord) {
        let duplicateLastPlayed = duplicate.lastPlayedDate ?? .distantPast
        let survivorLastPlayed = survivor.lastPlayedDate ?? .distantPast

        if duplicate.isPlayed && (!survivor.isPlayed || duplicateLastPlayed > survivorLastPlayed) {
            survivor.isPlayed = true
            survivor.playbackPosition = duplicate.playbackPosition
            survivor.lastPlayedDate = duplicate.lastPlayedDate
        } else if !survivor.isPlayed {
            survivor.playbackPosition = max(survivor.playbackPosition, duplicate.playbackPosition)
        }

        if survivor.queuePosition == nil {
            survivor.queuePosition = duplicate.queuePosition
        }
    }
}
