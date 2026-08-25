//
//  VideoDisplayPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic for the iOS Audio/Video toggle's actual effect, pulled out so it's
/// testable without AudioPlayerManager/AVPlayer. See VIDEO_PLAYBACK_PLAN.md Phase 5 and its
/// video-only "look away for audio-only" addendum.
///
/// The toggle looks the same for every episode with a video enclosure, but it means two
/// different things depending on whether the episode also has a separate audio enclosure:
/// - Mixed episode (both exist): selecting a segment is a real source switch - the same
///   switchMediaKind(to:) flow this app has had since Phase 2.
/// - Video-only episode: there's nothing to switch *to* for "Audio", so selecting it just hides
///   the video frame (falling back to episode artwork) while the same video item keeps playing -
///   the audio track was always there, this just stops paying attention to the video track (and,
///   via VideoInlinePolicy.shouldEnableVideoTrack, stops decoding it).
enum VideoDisplayPolicy {
    enum Plan: Equatable {
        /// Actually reload the player onto the other enclosure - VideoDisplayPolicy defers to
        /// AudioPlayerManager.switchMediaKind(to:) for engineering exact seek/rate carry-over.
        case switchSource(to: MediaKind)
        /// No source change - just show or hide the video frame in NowPlayingView.
        case setFrameVisible(Bool)
    }

    static func plan(requestedKind: MediaKind, currentMediaKind: MediaKind, hasAudioURL: Bool) -> Plan {
        // Already loaded - nothing to switch, this is purely a frame-visibility request (the
        // video-only "hide the frame" / "show it again" round trip).
        if requestedKind == currentMediaKind {
            return .setFrameVisible(requestedKind == .video)
        }
        // Requesting audio with nothing to switch to (video-only episode) - hide the frame
        // rather than attempt (and silently no-op) a source switch.
        if requestedKind == .audio && !hasAudioURL {
            return .setFrameVisible(false)
        }
        return .switchSource(to: requestedKind)
    }
}
