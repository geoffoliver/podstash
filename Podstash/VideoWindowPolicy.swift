//
//  VideoWindowPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic for AudioPlayerManager's macOS video window handling, pulled out so it's
/// testable without NSWindow/AVPlayerView. See VIDEO_PLAYBACK_PLAN.md Phase 4.
enum VideoWindowPolicy {
    /// Whether the video window should be (auto-)opened for the given currently-loaded kind.
    /// True only when the kind is video and the window isn't already open - covers both
    /// play(episode:) resolving to video (video-only episode, nothing to fall back to) and
    /// resume() finding mediaKind still at .video after a prior close left it there (see
    /// closeAction below).
    static func shouldOpenVideoWindow(mediaKind: MediaKind, isWindowOpen: Bool) -> Bool {
        mediaKind == .video && !isWindowOpen
    }

    /// Whether the "Open Video" button should be shown in the transport controls: whenever the
    /// current episode has a video enclosure and the window isn't already open.
    static func showOpenVideoButton(hasVideoURL: Bool, isWindowOpen: Bool) -> Bool {
        hasVideoURL && !isWindowOpen
    }

    enum CloseAction: Equatable {
        /// Pause, then switch back to the audio enclosure (position carries over) - the window
        /// has to be reopened explicitly (via "Open Video") to watch again.
        case pauseAndSwitchToAudio
        /// Pause only, leaving mediaKind at .video since there's no audio to fall back to - the
        /// next Play naturally reopens the window via shouldOpenVideoWindow.
        case pauseOnly
    }

    /// What closing the video window should do. Closing always stops playback entirely (a
    /// deliberate divergence from "keep playing in the background" - that's iOS-only, see Phase
    /// 5): closing the window is a clear, visible user action on macOS, not an ambient
    /// backgrounding event.
    static func closeAction(hasAudioURL: Bool) -> CloseAction {
        hasAudioURL ? .pauseAndSwitchToAudio : .pauseOnly
    }
}
