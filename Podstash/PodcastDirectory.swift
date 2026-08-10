//
//  PodcastDirectory.swift
//  Podstash
//

import Foundation
import SwiftData
import SwiftUI
import Combine

/// Resolves `Episode.podcastID -> Podcast`. Episode has no relationship to Podcast (it lives in
/// a different, local-only ModelConfiguration - see PodstashApp.sharedModelContainer), so every
/// call site that used to read `episode.podcast` looks the podcast up here instead. Only ~38
/// rows, changes rarely (subscribe/unsubscribe), so a single cached dictionary beats a
/// FetchDescriptor per row render.
@MainActor
final class PodcastDirectory: ObservableObject {
    @Published private(set) var byID: [UUID: Podcast] = [:]

    func update(_ podcasts: [Podcast]) {
        byID = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.id, $0) })
    }

    func podcast(for id: UUID) -> Podcast? {
        byID[id]
    }
}

/// Bridges SwiftData's `@Query` (usable only inside a View) into a plain ObservableObject so
/// non-View types (AudioPlayerManager, MenuCoordinator) can resolve podcasts too. Wrap once, at
/// the root of the view tree, not per-screen.
struct PodcastDirectoryProvider<Content: View>: View {
    @Query(sort: \Podcast.title) private var podcasts: [Podcast]
    @StateObject private var directory = PodcastDirectory()
    let content: (PodcastDirectory) -> Content

    var body: some View {
        content(directory)
            .environmentObject(directory)
            .onAppear { directory.update(podcasts) }
            .onChange(of: podcasts) { _, newPodcasts in directory.update(newPodcasts) }
    }
}
