//
//  PlaybackRecordStoreTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
@testable import Podstash

@MainActor
// .serialized - see the comment on FeedFetcherTests' @Suite for why (each test creates its own
// in-memory ModelContainer; concurrent tests race CoreData's connection pool).
@Suite("PlaybackRecordStore", .serialized)
struct PlaybackRecordStoreTests {

    /// Fresh container per test, on a temp on-disk store - never touches CloudKit or the real
    /// on-disk app store. Not isStoredInMemoryOnly: true - that configuration reliably crashes
    /// ("No eligible connection available") on the macOS 27 beta SDK this targets.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Podcast.self, Episode.self, PlaybackRecord.self])
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
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

    // MARK: - markPlayed

    @Test("markPlayed sets isPlayed and advances the podcast's mostRecentlyPlayedDate from nil")
    func markPlayedAdvancesWatermarkFromNil() throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed")
        context.insert(podcast)
        let publishDate = Date.now.addingTimeInterval(-1000)
        let episode = Episode(title: "Ep", audioURL: "https://example.com/e.mp3", publishDate: publishDate, podcastID: podcast.id)
        context.insert(episode)
        try context.save()

        let record = PlaybackRecordStore.markPlayed(episode: episode, in: context)

        #expect(record.isPlayed == true)
        #expect(podcast.mostRecentlyPlayedDate == publishDate)
    }

    @Test("markPlayed does not regress the podcast's mostRecentlyPlayedDate when it's already newer")
    func markPlayedDoesNotRegressWatermark() throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed")
        let newerDate = Date.now
        podcast.mostRecentlyPlayedDate = newerDate
        context.insert(podcast)
        let olderPublishDate = Date.now.addingTimeInterval(-5000)
        let episode = Episode(title: "Ep", audioURL: "https://example.com/e.mp3", publishDate: olderPublishDate, podcastID: podcast.id)
        context.insert(episode)
        try context.save()

        _ = PlaybackRecordStore.markPlayed(episode: episode, in: context)

        #expect(podcast.mostRecentlyPlayedDate == newerDate)
    }

    // MARK: - nextQueuePosition

    @Test("nextQueuePosition is 0 when nothing is queued")
    func nextQueuePositionStartsAtZero() throws {
        let context = try makeContext()
        #expect(PlaybackRecordStore.nextQueuePosition(in: context) == 0)
    }

    @Test("nextQueuePosition is one past the current maximum queuePosition")
    func nextQueuePositionFollowsMaximum() throws {
        let context = try makeContext()
        context.insert(PlaybackRecord(episodeKey: "a", queuePosition: 0))
        context.insert(PlaybackRecord(episodeKey: "b", queuePosition: 3))
        try context.save()

        #expect(PlaybackRecordStore.nextQueuePosition(in: context) == 4)
    }

    // MARK: - firstByKey

    @Test("firstByKey keys episodes by episodeKey")
    func firstByKeyKeysEpisodes() {
        let episode = Episode(title: "One", audioURL: "https://example.com/e.mp3", guid: "key-1", publishDate: .now, podcastID: UUID())

        let byKey = PlaybackRecordStore.firstByKey([episode])

        #expect(byKey["key-1"] === episode)
    }

    // Real-world feeds have shipped two items sharing a <guid> (e.g. duplicate art19 locators),
    // which would otherwise crash Dictionary(uniqueKeysWithValues:) - see QueueView.queuedEpisodes.
    @Test("firstByKey keeps the first episode when two share an episodeKey, instead of crashing")
    func firstByKeyKeepsFirstOnDuplicateKey() {
        let first = Episode(title: "First", audioURL: "https://example.com/a.mp3", guid: "dup-key", publishDate: .now, podcastID: UUID())
        let second = Episode(title: "Second", audioURL: "https://example.com/b.mp3", guid: "dup-key", publishDate: .now, podcastID: UUID())

        let byKey = PlaybackRecordStore.firstByKey([first, second])

        #expect(byKey.count == 1)
        #expect(byKey["dup-key"] === first)
    }
}
