//
//  SubscriptionManagerTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
@testable import Podstash

@MainActor
// .serialized - see the comment on FeedFetcherTests' @Suite for why (each test creates its own
// in-memory ModelContainer; concurrent tests race CoreData's connection pool).
@Suite("SubscriptionManager", .serialized)
struct SubscriptionManagerTests {

    // Uses a temp on-disk store, not isStoredInMemoryOnly: true - the in-memory configuration
    // reliably crashes ("No eligible connection available") on the macOS 27 beta SDK this
    // targets. See the identical comment/fix in FeedFetcherTests.swift.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Podcast.self, Episode.self, PlaybackRecord.self])
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
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

    @Test("unsubscribe deletes PlaybackRecord history for the podcast's episodes")
    func unsubscribeDeletesPlaybackHistory() throws {
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
        #expect(survivingRecords.isEmpty)
    }

    @Test("Resubscribing under a different feed with an episode that reuses a guid from the unsubscribed feed doesn't inherit its stale play state")
    func resubscribeDoesNotInheritStalePlayStateAcrossGuidCollision() throws {
        // Some shows publish separate audio and video RSS feeds that reuse the same <guid> per
        // episode (it's just a link to the episode's webpage, not scoped to one feed variant) -
        // this is the exact scenario reported: unsubscribing from the audio feed and subscribing
        // to the video feed of the same show must not resurrect the audio feed's play history.
        let context = try makeContext()
        let sharedGuid = "https://showsite.example.com/episodes/42"

        let audioPodcast = Podcast(title: "Show (Audio)", feedURL: "https://example.com/audio.xml")
        context.insert(audioPodcast)
        let audioEpisode = Episode(title: "Ep 42", audioURL: "https://example.com/ep42.mp3", guid: sharedGuid, publishDate: .now, podcastID: audioPodcast.id)
        context.insert(audioEpisode)
        let record = PlaybackRecordStore.recordForMutation(episodeKey: audioEpisode.episodeKey, in: context)
        record.isPlayed = true
        record.playbackPosition = 1234
        try context.save()

        let manager = SubscriptionManager(modelContext: context)
        manager.unsubscribe(podcast: audioPodcast)

        let videoPodcast = Podcast(title: "Show (Video)", feedURL: "https://example.com/video.xml")
        context.insert(videoPodcast)
        let videoEpisode = Episode(title: "Ep 42", videoURL: "https://example.com/ep42.mp4", guid: sharedGuid, publishDate: .now, podcastID: videoPodcast.id)
        context.insert(videoEpisode)
        try context.save()

        #expect(videoEpisode.episodeKey == audioEpisode.episodeKey) // same guid -> same join key
        let state = PlaybackRecordStore.state(for: videoEpisode, in: context)
        #expect(state.isPlayed == false)
        #expect(state.playbackPosition == 0)
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

    @Test("unsubscribe(feedURL:) removes the podcast subscribed at that feed URL")
    func unsubscribeByFeedURLRemovesMatchingPodcast() throws {
        let context = try makeContext()
        let manager = SubscriptionManager(modelContext: context)
        _ = manager.subscribe(title: "Show", feedURL: "https://example.com/feed.xml")

        let result = manager.unsubscribe(feedURL: "https://example.com/feed.xml")

        #expect(result == true)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).isEmpty)
    }

    @Test("unsubscribe(feedURL:) returns false and changes nothing for an unknown feed URL")
    func unsubscribeByFeedURLIgnoresUnknownFeedURL() throws {
        let context = try makeContext()
        let manager = SubscriptionManager(modelContext: context)
        _ = manager.subscribe(title: "Show", feedURL: "https://example.com/feed.xml")

        let result = manager.unsubscribe(feedURL: "https://example.com/other.xml")

        #expect(result == false)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).count == 1)
    }

    @Test("subscribedFeedURLs returns the feed URL of every subscribed podcast")
    func subscribedFeedURLsReturnsAllFeedURLs() throws {
        let context = try makeContext()
        let manager = SubscriptionManager(modelContext: context)
        _ = manager.subscribe(title: "A", feedURL: "https://example.com/a.xml")
        _ = manager.subscribe(title: "B", feedURL: "https://example.com/b.xml")

        let feedURLs = manager.subscribedFeedURLs()

        #expect(feedURLs == ["https://example.com/a.xml", "https://example.com/b.xml"])
    }
}
