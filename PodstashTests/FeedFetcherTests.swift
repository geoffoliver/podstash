//
//  FeedFetcherTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
@testable import Podstash

@MainActor
@Suite("FeedFetcher episode matching")
struct FeedFetcherTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Podcast.self, Episode.self, PlaybackRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeParsedEpisode(
        audioURL: String,
        guid: String? = nil,
        publishDate: Date = .now
    ) -> ParsedEpisode {
        ParsedEpisode(title: "Episode", description: nil, audioURL: audioURL, guid: guid, duration: nil, publishDate: publishDate, artworkURL: nil)
    }

    private func makeParsedPodcast(episodes: [ParsedEpisode]) -> ParsedPodcast {
        ParsedPodcast(title: "Feed", description: nil, artworkURL: nil, author: nil, websiteURL: nil, episodes: episodes)
    }

    // downloadManager is left nil (FeedFetcher's default) throughout - that keeps
    // settings.autoDownloadNewEpisodes from ever triggering a real network download while still
    // exercising the matching/dedup/watermark logic these tests target.

    @Test("An item already stored under its guid is not recreated, even if its audioURL rotated")
    func guidMatchPreventsDuplicateDespiteURLChange() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        context.insert(Episode(title: "Ep 1", audioURL: "https://cdn.example.com/token-old/ep1.mp3", guid: "ep-1", publishDate: .now, podcastID: podcast.id))
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed = makeParsedEpisode(audioURL: "https://cdn.example.com/token-new/ep1.mp3", guid: "ep-1")

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed]),
            parsedEpisodes: [parsed],
            updateTimestamp: false,
            shouldSave: false
        )

        #expect(try context.fetch(FetchDescriptor<Episode>()).count == 1)
    }

    @Test("An item previously matched only by audioURL gets its guid backfilled")
    func audioURLMatchBackfillsGUID() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        context.insert(Episode(title: "Ep 2", audioURL: "https://example.com/ep2.mp3", guid: nil, publishDate: .now, podcastID: podcast.id))
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed = makeParsedEpisode(audioURL: "https://example.com/ep2.mp3", guid: "ep-2")

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed]),
            parsedEpisodes: [parsed],
            updateTimestamp: false,
            shouldSave: false
        )

        let all = try context.fetch(FetchDescriptor<Episode>())
        #expect(all.count == 1)
        #expect(all.first?.guid == "ep-2")
    }

    @Test("A feed listing the same item twice in one refresh creates only one Episode row")
    func duplicateItemInSingleRefreshCreatesOneRow() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed1 = makeParsedEpisode(audioURL: "https://example.com/ep3.mp3", guid: "ep-3")
        let parsed2 = makeParsedEpisode(audioURL: "https://example.com/ep3.mp3", guid: "ep-3")

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed1, parsed2]),
            parsedEpisodes: [parsed1, parsed2],
            updateTimestamp: false,
            shouldSave: false
        )

        #expect(try context.fetch(FetchDescriptor<Episode>()).count == 1)
    }

    @Test("newestKnownPublishDate advances to the newest item seen, even when nothing new is created")
    func watermarkAdvancesEvenWithoutNewEpisodes() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        podcast.newestKnownPublishDate = Date.now.addingTimeInterval(-10 * 86400) // stale
        context.insert(podcast)
        let existingDate = Date.now.addingTimeInterval(-86400)
        context.insert(Episode(title: "Ep 4", audioURL: "https://example.com/ep4.mp3", guid: "ep-4", publishDate: existingDate, podcastID: podcast.id))
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        // Still listed by the feed, matched by guid so nothing new is created - but its
        // publishDate is newer than the stale watermark and should still advance it.
        let parsed = makeParsedEpisode(audioURL: "https://example.com/ep4.mp3", guid: "ep-4", publishDate: existingDate)

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed]),
            parsedEpisodes: [parsed],
            updateTimestamp: false,
            shouldSave: false
        )

        #expect(podcast.newestKnownPublishDate == existingDate)
    }
}
