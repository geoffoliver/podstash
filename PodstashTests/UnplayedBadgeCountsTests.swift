//
//  UnplayedBadgeCountsTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
@testable import Podstash

@MainActor
// .serialized - see the comment on FeedFetcherTests' @Suite for why (each test creates its own
// on-disk ModelContainer; concurrent tests race CoreData's connection pool).
@Suite("UnplayedBadgeCounts", .serialized)
struct UnplayedBadgeCountsTests {

    /// Same temp on-disk store setup as PlaybackRecordStoreTests - see that file for why it isn't
    /// isStoredInMemoryOnly.
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Podcast.self, Episode.self, PlaybackRecord.self])
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private let day: TimeInterval = 86_400

    @Test("Counts downloaded, unplayed episodes per podcast and skips played ones")
    func countsDownloadedUnplayed() throws {
        let context = try makeContext()
        let podcast = Podcast(title: "A", feedURL: "https://example.com/a")
        context.insert(podcast)
        let unplayed = Episode(title: "1", guid: "a-1", publishDate: .now.addingTimeInterval(-10 * day), isDownloaded: true, podcastID: podcast.id)
        let played = Episode(title: "2", guid: "a-2", publishDate: .now.addingTimeInterval(-9 * day), isDownloaded: true, podcastID: podcast.id)
        context.insert(unplayed)
        context.insert(played)
        context.insert(PlaybackRecord(episodeKey: "a-2", isPlayed: true))
        try context.save()

        let counts = UnplayedBadgeCounts.counts(for: [podcast], in: context)

        #expect(counts[podcast.id] == 1)
    }

    @Test("Counts non-downloaded episodes newer than the podcast's mostRecentlyPlayedDate")
    func countsNewerThanMostRecentlyPlayed() throws {
        let context = try makeContext()
        let playedDate = Date.now.addingTimeInterval(-5 * day)
        let podcast = Podcast(title: "A", feedURL: "https://example.com/a", newestKnownPublishDate: .now, mostRecentlyPlayedDate: playedDate)
        context.insert(podcast)
        context.insert(Episode(title: "old", guid: "a-old", publishDate: playedDate.addingTimeInterval(-day), podcastID: podcast.id))
        context.insert(Episode(title: "new", guid: "a-new", publishDate: playedDate.addingTimeInterval(day), podcastID: podcast.id))
        try context.save()

        let counts = UnplayedBadgeCounts.counts(for: [podcast], in: context)

        #expect(counts[podcast.id] == 1)
    }

    // The regression this guards: candidates used to be fetched with ONE publishDate bound - the
    // earliest threshold across every podcast - so a single long-dead feed (threshold years in
    // the past) dragged every other podcast's entire recent back-catalog into memory on each
    // recompute (~7,000 Episode objects in a real library, every 3 seconds, on the main thread).
    @Test("Candidates are bounded per podcast, so one podcast's old threshold doesn't pull in another podcast's older episodes")
    func candidatesBoundedPerPodcast() throws {
        let context = try makeContext()
        let dead = Podcast(title: "Dead", feedURL: "https://example.com/dead", newestKnownPublishDate: .now.addingTimeInterval(-1000 * day))
        let active = Podcast(title: "Active", feedURL: "https://example.com/active", newestKnownPublishDate: .now, mostRecentlyPlayedDate: .now.addingTimeInterval(-2 * day))
        context.insert(dead)
        context.insert(active)
        // Older than `active`'s own threshold, but newer than `dead`'s.
        let activeBackCatalog = Episode(title: "back", guid: "active-back", publishDate: .now.addingTimeInterval(-100 * day), podcastID: active.id)
        let activeNew = Episode(title: "new", guid: "active-new", publishDate: .now.addingTimeInterval(-day), podcastID: active.id)
        context.insert(activeBackCatalog)
        context.insert(activeNew)
        try context.save()

        let candidateKeys = Set(UnplayedBadgeCounts.candidateEpisodes(for: [dead, active], in: context).map(\.episodeKey))

        #expect(candidateKeys == ["active-new"])
    }

    @Test("Downloaded episodes are always candidates, even when older than their podcast's threshold")
    func downloadedAlwaysCandidates() throws {
        let context = try makeContext()
        let podcast = Podcast(title: "A", feedURL: "https://example.com/a", newestKnownPublishDate: .now, mostRecentlyPlayedDate: .now)
        context.insert(podcast)
        context.insert(Episode(title: "old", guid: "a-old", publishDate: .now.addingTimeInterval(-500 * day), isDownloaded: true, podcastID: podcast.id))
        try context.save()

        let candidateKeys = Set(UnplayedBadgeCounts.candidateEpisodes(for: [podcast], in: context).map(\.episodeKey))

        #expect(candidateKeys == ["a-old"])
    }
}
