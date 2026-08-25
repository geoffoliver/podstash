//
//  RefreshProgress.swift
//  Podstash
//

import Foundation
import Combine

/// The part of refresh state that changes on every progress tick during a refresh -
/// currentPodcastTitle/progress update roughly once per podcast processed (throttled, see
/// FeedFetcher.fetchFeeds). Deliberately a separate ObservableObject from RefreshCoordinator
/// itself, mirroring PlaybackProgress's split from AudioPlayerManager for the same reason:
/// SwiftUI's @EnvironmentObject subscription is all-or-nothing per object, not per property, so
/// any view holding RefreshCoordinator directly re-renders on every one of its @Published
/// changes - including these - regardless of whether that view's body actually reads them. That
/// was silently forcing PodcastListView's badge-count recompute to rerun on every progress tick
/// of a refresh it doesn't display, not just when the badge-relevant data actually changed. Only
/// RefreshStatusBar's call sites (in ContentView) need live progress; PodcastListView holds
/// RefreshCoordinator itself for isRefreshing, which only changes twice per refresh (start/end).
@MainActor
final class RefreshProgress: ObservableObject {
    @Published var currentPodcastTitle: String?
    @Published var progress: (current: Int, total: Int)?
}
