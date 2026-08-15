//
//  SubscriptionManagerTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
@testable import Podstash

@MainActor
@Suite("SubscriptionManager")
struct SubscriptionManagerTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Podcast.self, Episode.self, PlaybackRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test("subscribe creates a new podcast and returns true")
    func subscribeCreatesPodcast() throws {
        let context = try makeContext()
        let manager = SubscriptionManager(modelContext: context)

        let result = manager.subscribe(title: "Show", feedURL: "https://example.com/feed.xml")

        #expect(result == true)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).count == 1)
    }

    @Test("subscribing to an already-subscribed feed URL returns false and does not duplicate")
    func subscribeRejectsDuplicateFeedURL() throws {
        let context = try makeContext()
        let manager = SubscriptionManager(modelContext: context)
        _ = manager.subscribe(title: "Show", feedURL: "https://example.com/feed.xml")

        let result = manager.subscribe(title: "Show Again", feedURL: "https://example.com/feed.xml")

        #expect(result == false)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).count == 1)
    }

    @Test("unsubscribe deletes the podcast and its local episode rows")
    func unsubscribeDeletesPodcastAndEpisodes() throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        context.insert(Episode(title: "Ep", audioURL: "https://example.com/ep.mp3", publishDate: .now, podcastID: podcast.id))
        try context.save()

        let manager = SubscriptionManager(modelContext: context)
        let result = manager.unsubscribe(podcast: podcast)

        #expect(result == true)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Episode>()).isEmpty)
    }

    @Test("unsubscribe clears queuePosition but preserves play history")
    func unsubscribeDequeuesButKeepsPlayHistory() throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        let episode = Episode(title: "Ep", audioURL: "https://example.com/ep.mp3", publishDate: .now, podcastID: podcast.id)
        context.insert(episode)
        let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: context)
        record.queuePosition = 2
        record.isPlayed = true
        record.playbackPosition = 42
        try context.save()

        let episodeKey = episode.episodeKey
        let manager = SubscriptionManager(modelContext: context)
        manager.unsubscribe(podcast: podcast)

        let survivingRecords = try context.fetch(FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.episodeKey == episodeKey }))
        let survivor = try #require(survivingRecords.first)
        #expect(survivor.queuePosition == nil)
        #expect(survivor.isPlayed == true)
        #expect(survivor.playbackPosition == 42)
    }

    @Test("unsubscribing multiple podcasts removes every podcast's episodes in one call")
    func unsubscribeMultiplePodcasts() throws {
        let context = try makeContext()
        let podcastA = Podcast(title: "A", feedURL: "https://example.com/a.xml")
        let podcastB = Podcast(title: "B", feedURL: "https://example.com/b.xml")
        context.insert(podcastA)
        context.insert(podcastB)
        context.insert(Episode(title: "A1", audioURL: "https://example.com/a1.mp3", publishDate: .now, podcastID: podcastA.id))
        context.insert(Episode(title: "B1", audioURL: "https://example.com/b1.mp3", publishDate: .now, podcastID: podcastB.id))
        try context.save()

        let manager = SubscriptionManager(modelContext: context)
        let result = manager.unsubscribe(podcasts: [podcastA, podcastB])

        #expect(result == true)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Episode>()).isEmpty)
    }
}
