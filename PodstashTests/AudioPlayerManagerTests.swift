//
//  AudioPlayerManagerTests.swift
//  PodstashTests
//

import Testing
import Foundation
import SwiftData
import AVFoundation
@testable import Podstash

@MainActor
// .serialized - see the comment on FeedFetcherTests' @Suite for why (each test creates its own
// in-memory ModelContainer; concurrent tests race CoreData's connection pool).
@Suite("AudioPlayerManager", .serialized)
struct AudioPlayerManagerTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Podcast.self, Episode.self, PlaybackRecord.self])
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let configuration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    // Regression: switching episodes never removed the NotificationCenter observer registered
    // for the PREVIOUS episode's AVPlayerItem (see setupNotifications/teardownPlayerItem). That
    // stale registration is scoped by object identity to the old, discarded item, so in principle
    // it should never fire again - but AVFoundation/ARC can and does reuse a deallocated
    // AVPlayerItem's memory address for a later one, especially when a queue auto-advances
    // through several episodes back to back. Retaining a reference to the old item and posting
    // its completion notification after switching reproduces that exact effect without depending
    // on incidental memory reuse: it drives playerDidFinishPlaying a second, spurious time against
    // whatever episode is `currentEpisode` by then - silently marking an unrelated, never-played
    // episode played and dropping it from the queue.
    @Test("A stale end-of-playback observer from a previous episode does not mark the new current episode played")
    func staleObserverDoesNotMarkUnrelatedEpisodePlayed() async throws {
        let context = try makeContext()
        let podcast = Podcast(title: "Show", feedURL: "https://example.com/feed")
        context.insert(podcast)
        let episodeA = Episode(title: "A", audioURL: "file:///tmp/podstash-test-a.mp3", guid: "a", publishDate: .now, podcastID: podcast.id)
        let episodeB = Episode(title: "B", audioURL: "file:///tmp/podstash-test-b.mp3", guid: "b", publishDate: .now, podcastID: podcast.id)
        context.insert(episodeA)
        context.insert(episodeB)
        try context.save()

        let manager = AudioPlayerManager()
        manager.setModelContext(context)

        manager.play(episode: episodeA)
        let staleItem = manager.playerForVideoSurface?.currentItem

        manager.play(episode: episodeB)

        // Simulate episode A's now-stale completion observer firing, as happens when a later
        // AVPlayerItem reuses A's freed memory address.
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: staleItem)

        // playerDidFinishPlaying's body runs in a Task { @MainActor in ... } enqueued by the
        // notification post - give it a chance to actually run before asserting.
        for _ in 0..<20 {
            await Task.yield()
        }

        let stateB = PlaybackRecordStore.state(for: episodeB, in: context)
        #expect(stateB.isPlayed == false)
    }
}
