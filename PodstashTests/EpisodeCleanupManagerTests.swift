//
//  EpisodeCleanupManagerTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
@testable import Podstash

@MainActor
// .serialized - see the comment on FeedFetcherTests' @Suite for why (each test creates its own
// in-memory ModelContainer; concurrent tests race CoreData's connection pool).
@Suite("EpisodeCleanupManager", .serialized)
struct EpisodeCleanupManagerTests {

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

    /// AppSettings is backed by UserDefaults.standard, which for this sandboxed app is the same
    /// container the real, installed Podstash.app reads (see AppSettings.swift) - a test must
    /// never leave the developer's actual retention preferences mutated. Snapshots the handful of
    /// keys EpisodeCleanupManager reads and restores them (or their absence) once the test ends.
    private func withIsolatedRetentionSettings<T>(_ body: (AppSettings) throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        let keys = ["episodeRetentionPolicy", "autoDeletePlayedEpisodes", "autoDeleteAfterDays", "episodeRetentionCount"]
        let snapshot = defaults.dictionaryRepresentation().filter { keys.contains($0.key) }
        defer {
            for key in keys { defaults.removeObject(forKey: key) }
            for (key, value) in snapshot { defaults.set(value, forKey: key) }
        }
        return try body(AppSettings())
    }

    @discardableResult
    private func makeDownloadedEpisode(
        in context: ModelContext,
        podcastID: UUID,
        publishDate: Date = .now,
        isPlayed: Bool = false,
        lastPlayedDate: Date? = nil
    ) throws -> Episode {
        let episode = Episode(
            title: "Episode",
            audioURL: "https://example.com/\(UUID().uuidString).mp3",
            publishDate: publishDate,
            isDownloaded: true,
            downloadedFilename: "\(UUID().uuidString).mp3",
            podcastID: podcastID
        )
        context.insert(episode)
        if isPlayed || lastPlayedDate != nil {
            let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: context)
            record.isPlayed = isPlayed
            record.lastPlayedDate = lastPlayedDate
        }
        try context.save()
        return episode
    }

    @Test("unplayedOnly policy reclaims every played download and keeps unplayed ones")
    func unplayedOnlyReclaimsPlayed() throws {
        try withIsolatedRetentionSettings { settings in
            let context = try makeContext()
            let podcastID = UUID()
            let played = try makeDownloadedEpisode(in: context, podcastID: podcastID, isPlayed: true)
            let unplayed = try makeDownloadedEpisode(in: context, podcastID: podcastID, isPlayed: false)

            settings.episodeRetentionPolicy = EpisodeRetentionPolicy.unplayedOnly.rawValue
            EpisodeCleanupManager(modelContext: context, settings: settings).cleanupEpisodes()

            #expect(played.isDownloaded == false)
            #expect(played.downloadedFilename == nil)
            #expect(unplayed.isDownloaded == true)
        }
    }

    @Test("all policy with autoDeletePlayedEpisodes disabled keeps every download")
    func allPolicyKeepsEverythingWhenAutoDeleteDisabled() throws {
        try withIsolatedRetentionSettings { settings in
            let context = try makeContext()
            let played = try makeDownloadedEpisode(in: context, podcastID: UUID(), isPlayed: true, lastPlayedDate: .distantPast)

            settings.episodeRetentionPolicy = EpisodeRetentionPolicy.all.rawValue
            settings.autoDeletePlayedEpisodes = false
            EpisodeCleanupManager(modelContext: context, settings: settings).cleanupEpisodes()

            #expect(played.isDownloaded == true)
        }
    }

    @Test("all policy with autoDeletePlayedEpisodes reclaims only played downloads older than the cutoff")
    func allPolicyReclaimsOnlyOldPlayed() throws {
        try withIsolatedRetentionSettings { settings in
            let context = try makeContext()
            let podcastID = UUID()
            let oldPlayed = try makeDownloadedEpisode(
                in: context, podcastID: podcastID, isPlayed: true,
                lastPlayedDate: Calendar.current.date(byAdding: .day, value: -30, to: .now)
            )
            let recentPlayed = try makeDownloadedEpisode(in: context, podcastID: podcastID, isPlayed: true, lastPlayedDate: .now)
            let unplayed = try makeDownloadedEpisode(in: context, podcastID: podcastID, isPlayed: false)

            settings.episodeRetentionPolicy = EpisodeRetentionPolicy.all.rawValue
            settings.autoDeletePlayedEpisodes = true
            settings.autoDeleteAfterDays = 7
            EpisodeCleanupManager(modelContext: context, settings: settings).cleanupEpisodes()

            #expect(oldPlayed.isDownloaded == false)
            #expect(recentPlayed.isDownloaded == true)
            #expect(unplayed.isDownloaded == true)
        }
    }

    @Test("mostRecent policy only reclaims played downloads beyond the retained count")
    func mostRecentPolicyReclaimsBeyondCount() throws {
        try withIsolatedRetentionSettings { settings in
            let context = try makeContext()
            let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed.xml")
            context.insert(podcast)

            let now = Date.now
            // Newest first; only the most recent 2 are retained.
            let newest = try makeDownloadedEpisode(in: context, podcastID: podcast.id, publishDate: now, isPlayed: true)
            let middle = try makeDownloadedEpisode(in: context, podcastID: podcast.id, publishDate: now.addingTimeInterval(-86400), isPlayed: true)
            let oldestPlayed = try makeDownloadedEpisode(in: context, podcastID: podcast.id, publishDate: now.addingTimeInterval(-2 * 86400), isPlayed: true)
            let oldestUnplayed = try makeDownloadedEpisode(in: context, podcastID: podcast.id, publishDate: now.addingTimeInterval(-3 * 86400), isPlayed: false)

            settings.episodeRetentionPolicy = EpisodeRetentionPolicy.mostRecent.rawValue
            settings.episodeRetentionCount = 2
            EpisodeCleanupManager(modelContext: context, settings: settings).cleanupEpisodes()

            #expect(newest.isDownloaded == true)
            #expect(middle.isDownloaded == true)
            #expect(oldestPlayed.isDownloaded == false)
            #expect(oldestUnplayed.isDownloaded == true) // unplayed downloads are never auto-deleted
        }
    }
}
