//
//  VideoDownloadPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic for gating video downloads on Wi-Fi, pulled out so it's testable without
/// a real network path. See VIDEO_PLAYBACK_PLAN.md Phase 6 - only video downloads are ever
/// gated; audio downloads are unaffected by downloadVideoOnWiFiOnly regardless of connection.
enum VideoDownloadPolicy {
    static func shouldDownloadNow(mediaKind: MediaKind, downloadVideoOnWiFiOnly: Bool, isOnWiFi: Bool) -> Bool {
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
