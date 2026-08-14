//
//  PlaybackRecordStoreTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
@testable import Podstash

@MainActor
@Suite("PlaybackRecordStore")
struct PlaybackRecordStoreTests {

    /// Fresh in-memory container per test - never touches CloudKit or the real on-disk store.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Podcast.self, Episode.self, PlaybackRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test("recordForMutation creates exactly one record per key")
    func recordForMutationIsIdempotent() throws {
        let context = try makeContext()

        let first = PlaybackRecordStore.recordForMutation(episodeKey: "key-1", in: context)
        first.isPlayed = true
        let second = PlaybackRecordStore.recordForMutation(episodeKey: "key-1", in: context)

        #expect(first === second)
        #expect(try context.fetch(FetchDescriptor<PlaybackRecord>()).count == 1)
    }

    @Test("An episode with no PlaybackRecord resolves to default state")
    func missingRecordResolvesToDefaults() throws {
        let context = try makeContext()
        let episode = Episode(title: "New", audioURL: "https://example.com/e.mp3", publishDate: .now, podcastID: UUID())

        let state = PlaybackRecordStore.state(for: episode, in: context)

        #expect(state == EpisodeState())
    }

    @Test("deduplicate merges two records for the same key, preferring isPlayed=true")
    func deduplicatePrefersPlayed() throws {
        let context = try makeContext()
        context.insert(PlaybackRecord(episodeKey: "dup", isPlayed: false, playbackPosition: 500))
        context.insert(PlaybackRecord(episodeKey: "dup", isPlayed: true, playbackPosition: 100, lastPlayedDate: .now))
        try context.save()

        PlaybackRecordStore.deduplicate(in: context)

        let survivors = try context.fetch(FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.episodeKey == "dup" }))
        #expect(survivors.count == 1)
        #expect(survivors.first?.isPlayed == true)
    }

    @Test("deduplicate keeps the larger playback position when neither record is played")
    func deduplicatePrefersFurtherProgress() throws {
        let context = try makeContext()
        context.insert(PlaybackRecord(episodeKey: "dup2", isPlayed: false, playbackPosition: 120))
        context.insert(PlaybackRecord(episodeKey: "dup2", isPlayed: false, playbackPosition: 900))
        try context.save()

        PlaybackRecordStore.deduplicate(in: context)

        let survivors = try context.fetch(FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.episodeKey == "dup2" }))
        #expect(survivors.count == 1)
        #expect(survivors.first?.playbackPosition == 900)
    }

    @Test("deduplicate carries over queuePosition from the duplicate when the survivor lacks one")
    func deduplicateFillsInMissingQueuePosition() throws {
        let context = try makeContext()
        context.insert(PlaybackRecord(episodeKey: "dup3"))
        context.insert(PlaybackRecord(episodeKey: "dup3", queuePosition: 2))
        try context.save()

        PlaybackRecordStore.deduplicate(in: context)

        let survivors = try context.fetch(FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.episodeKey == "dup3" }))
        #expect(survivors.count == 1)
        #expect(survivors.first?.queuePosition == 2)
    }
}
