//
//  VideoDownloadPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic for gating video downloads on Wi-Fi, pulled out so it's testable without
/// a real network path. See VIDEO_PLAYBACK_PLAN.md Phase 6 - only video downloads are ever
/// gated; audio downloads are unaffected by downloadVideoOnWiFiOnly regardless of connection.
enum VideoDownloadPolicy {
    /// Whether a download should start (or queue) right now. Manual downloads - a user's
    /// explicit "Download" tap - always proceed regardless of Wi-Fi; downloadVideoOnWiFiOnly
    /// only ever defers an automatic download (FeedFetcher's post-refresh auto-download pass).
    /// Same precedent as refreshOnlyOnWiFi gating only AutoRefreshManager's background refresh,
    /// never a user-initiated manual one.
    static func shouldDownloadNow(mediaKind: MediaKind, downloadVideoOnWiFiOnly: Bool, isOnWiFi: Bool, isManual: Bool) -> Bool {
        guard !isManual else { return true }
        guard mediaKind == .video, downloadVideoOnWiFiOnly else { return true }
        return isOnWiFi
    }

    /// Whether an auto-download pass (FeedFetcher's post-refresh downloads, gated by
    /// autoDownloadNewEpisodes) should include an episode of the given resolved kind. Video
    /// enclosures can be sizeable, so auto-download skips them unless the user opts in via
    /// autoDownloadVideoEpisodes - manual "download this episode" taps (PodcastDetailView,
    /// ContentView) never call through this function, so they're unaffected either way.
    static func shouldAutoDownload(mediaKind: MediaKind, autoDownloadVideoEpisodes: Bool) -> Bool {
        mediaKind == .audio || autoDownloadVideoEpisodes
    }
}
