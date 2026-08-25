//
//  FeedFetcherTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
@testable import Podstash

@MainActor
// .serialized: each test creates its own in-memory ModelContainer. Left to run concurrently
// (Swift Testing's default), several containers end up alive at once and race CoreData's SQLite
// connection pool - crashes intermittently with "No eligible connection available" on some
// macOS/Xcode betas. Serializing avoids the race regardless of the underlying bug.
@Suite("FeedFetcher episode matching", .serialized)
struct FeedFetcherTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Podcast.self, Episode.self, PlaybackRecord.self])
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeParsedEpisode(
        audioURL: String? = nil,
        videoURL: String? = nil,
        guid: String? = nil,
        publishDate: Date = .now
    ) -> ParsedEpisode {
        ParsedEpisode(title: "Episode", description: nil, audioURL: audioURL, videoURL: videoURL, guid: guid, duration: nil, publishDate: publishDate, artworkURL: nil)
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

    @Test("Two video-only episodes with distinct guids in the same refresh are not conflated by a shared nil audioURL")
    func videoOnlyEpisodesAreNotConflatedAcrossItems() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Video Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed1 = makeParsedEpisode(videoURL: "https://example.com/ep1.mp4", guid: "v-1")
        let parsed2 = makeParsedEpisode(videoURL: "https://example.com/ep2.mp4", guid: "v-2")

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed1, parsed2]),
            parsedEpisodes: [parsed1, parsed2],
            updateTimestamp: false,
            shouldSave: false
        )

        #expect(try context.fetch(FetchDescriptor<Episode>()).count == 2)
    }

    @Test("An item previously matched only by videoURL gets its guid backfilled")
    func videoURLMatchBackfillsGUID() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Video Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        context.insert(Episode(title: "Ep", audioURL: nil, videoURL: "https://example.com/ep.mp4", guid: nil, publishDate: .now, podcastID: podcast.id))
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed = makeParsedEpisode(videoURL: "https://example.com/ep.mp4", guid: "v-1")

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed]),
            parsedEpisodes: [parsed],
            updateTimestamp: false,
            shouldSave: false
        )

        let all = try context.fetch(FetchDescriptor<Episode>())
        #expect(all.count == 1)
        #expect(all.first?.guid == "v-1")
    }

    // MARK: - Legacy rows (created before video support existed, or before defaultMediaKind/
    // videoURL existed on the model) get backfilled on refresh - matched-but-stale episodes were
    // previously left untouched (just `continue`d past), permanently stuck with defaultMediaKind
    // and videoURL nil even once the feed's real video enclosure was available, which silently
    // broke downloading and playing them (MediaKindPolicy resolution fell back to a bogus
    // "audio" kind with no real audioURL to play).

    @Test("A guid-matched legacy row gets videoURL and defaultMediaKind backfilled from the fresh parse")
    func guidMatchBackfillsVideoSupportFields() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Video Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        // audioURL: "" mirrors the app's old non-optional `audioURL: String = ""` default - real
        // legacy rows have this exact value, not nil, per the old schema. defaultMediaKind is
        // nulled out after construction (rather than passed to init, which would just re-derive
        // it from audioURL) since a real legacy row never runs through init at all - SwiftData's
        // lightweight migration hydrates it directly from a column that didn't exist yet, leaving
        // it genuinely nil.
        let legacyEpisode = Episode(title: "Ep", audioURL: "", guid: "legacy-1", publishDate: .now, podcastID: podcast.id)
        legacyEpisode.defaultMediaKind = nil
        context.insert(legacyEpisode)
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed = ParsedEpisode(title: "Ep", description: nil, audioURL: nil, videoURL: "https://example.com/ep.mp4", defaultMediaKind: .video, guid: "legacy-1", duration: nil, publishDate: .now, artworkURL: nil)

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed]),
            parsedEpisodes: [parsed],
            updateTimestamp: false,
            shouldSave: false
        )

        let all = try context.fetch(FetchDescriptor<Episode>())
        #expect(all.count == 1)
        #expect(all.first?.videoURL == "https://example.com/ep.mp4")
        #expect(all.first?.defaultMediaKind == .video)
    }

    @Test("An audioURL-matched legacy row gets defaultMediaKind backfilled from the fresh parse")
    func audioURLMatchBackfillsMediaKind() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        let legacyEpisode = Episode(title: "Ep", audioURL: "https://example.com/ep.mp3", guid: nil, publishDate: .now, podcastID: podcast.id)
        legacyEpisode.defaultMediaKind = nil
        context.insert(legacyEpisode)
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed = ParsedEpisode(title: "Ep", description: nil, audioURL: "https://example.com/ep.mp3", videoURL: nil, defaultMediaKind: .audio, guid: "ep-audio", duration: nil, publishDate: .now, artworkURL: nil)

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed]),
            parsedEpisodes: [parsed],
            updateTimestamp: false,
            shouldSave: false
        )

        let all = try context.fetch(FetchDescriptor<Episode>())
        #expect(all.count == 1)
        #expect(all.first?.defaultMediaKind == .audio)
    }

    @Test("Backfill never overwrites a real, already-populated videoURL")
    func backfillDoesNotOverwriteExistingVideoURL() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Video Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        context.insert(Episode(title: "Ep", audioURL: nil, videoURL: "https://example.com/original.mp4", defaultMediaKind: .video, guid: "v-1", publishDate: .now, podcastID: podcast.id))
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed = ParsedEpisode(title: "Ep", description: nil, audioURL: nil, videoURL: "https://example.com/rotated.mp4", defaultMediaKind: .video, guid: "v-1", duration: nil, publishDate: .now, artworkURL: nil)

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed]),
            parsedEpisodes: [parsed],
            updateTimestamp: false,
            shouldSave: false
        )

        let all = try context.fetch(FetchDescriptor<Episode>())
        #expect(all.first?.videoURL == "https://example.com/original.mp4")
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

    // MARK: - Auto-queue

    @Test("A genuinely new episode newer than mostRecentlyPlayedDate is auto-queued")
    func newEpisodeNewerThanMostRecentlyPlayedIsAutoQueued() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        podcast.mostRecentlyPlayedDate = Date.now.addingTimeInterval(-10 * 86400)
        context.insert(podcast)
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let parsed = makeParsedEpisode(audioURL: "https://example.com/new.mp3", guid: "new-1", publishDate: .now)

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: [parsed]),
            parsedEpisodes: [parsed],
            updateTimestamp: false,
            shouldSave: false
        )

        let episode = try #require(try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.guid == "new-1" }))).first
        let record = try context.fetch(FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.episodeKey == "new-1" })).first
        #expect(episode != nil)
        #expect(record?.queuePosition != nil)
    }

    @Test("A fresh subscribe with no play history only auto-queues the single newest backlog episode")
    func freshSubscribeOnlyQueuesNewestEpisode() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
        context.insert(podcast)
        try context.save()

        let fetcher = FeedFetcher(modelContext: context, settings: AppSettings())
        let now = Date.now
        let parsedEpisodes = (0..<5).map { offset in
            makeParsedEpisode(audioURL: "https://example.com/ep\(offset).mp3", guid: "ep-\(offset)", publishDate: now.addingTimeInterval(TimeInterval(-offset * 86400)))
        }

        await fetcher.updatePodcastAndEpisodes(
            podcast: podcast,
            parsedPodcast: makeParsedPodcast(episodes: parsedEpisodes),
            parsedEpisodes: parsedEpisodes,
            updateTimestamp: false,
            shouldSave: false
        )

        let queuedRecords = try context.fetch(FetchDescriptor<PlaybackRecord>(predicate: #Predicate { $0.queuePosition != nil }))
        #expect(queuedRecords.count == 1)
        #expect(queuedRecords.first?.episodeKey == "ep-0")
    }
}
