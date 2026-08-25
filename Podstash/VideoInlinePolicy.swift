//
//  VideoInlinePolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic for NowPlayingView's iOS inline video handling, pulled out so it's
/// testable without AVPlayerLayer/UIKit. See VIDEO_PLAYBACK_PLAN.md Phase 5.
enum VideoInlinePolicy {
    /// Whether the Audio/Video segmented toggle should be shown - whenever the episode has a
    /// video enclosure at all, even a video-only one with no separate audio enclosure. In the
    /// video-only case "Audio" doesn't switch sources (see VideoDisplayPolicy) - it just hides
    /// the video frame so the user can listen without looking at it, matching what people expect
    /// from Apple Podcasts.
    static func showMediaKindToggle(hasVideoURL: Bool) -> Bool {
        hasVideoURL
    }

    /// Whether the video AVPlayerItemTrack should be enabled (decoding). True only while playing
    /// a video item AND the Now Playing surface showing it is actually visible AND the app is
    /// active AND the user actually wants to see the video frame right now (see
    /// VideoDisplayPolicy - a video-only episode can have mediaKind still .video while the user
    /// has chosen to hide the frame and listen audio-only). Background/dismiss the Now Playing
    /// view are never a media-kind switch (see the plan's governing rule), just a reason to stop
    /// paying for video decode while audio keeps playing. Re-enabling on foreground/reopen is the
    /// caller's job (AudioPlayerManager), driven by the same signals.
    static func shouldEnableVideoTrack(
        mediaKind: MediaKind,
        isAppActive: Bool,
        isNowPlayingSurfaceVisible: Bool,
        isVideoFrameVisible: Bool
    ) -> Bool {
        mediaKind == .video && isAppActive && isNowPlayingSurfaceVisible && isVideoFrameVisible
    }
}
