//
//  MediaKindPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic for AudioPlayerManager's audio/video handling, pulled out so it's testable
/// without AVPlayer. See VIDEO_PLAYBACK_PLAN.md Phase 2 - the governing rule is that which
/// enclosure is loaded only ever changes on an explicit user action, so the "what would change"
/// decision belongs here, separate from the AVFoundation calls that carry it out.
enum MediaKindPolicy {
    /// Mirrors Episode.init's own fallback (see Models.swift) for rows created before
    /// `defaultMediaKind` existed, where SwiftData's lightweight migration leaves it nil rather
    /// than backfilling a real value.
    static func resolvedDefaultKind(defaultMediaKind: MediaKind?, hasAudioURL: Bool) -> MediaKind {
        defaultMediaKind ?? (hasAudioURL ? .audio : .video)
    }

    /// The enclosure URL string for a given kind, or nil if the episode doesn't have one.
    static func urlString(for kind: MediaKind, audioURL: String?, videoURL: String?) -> String? {
        switch kind {
        case .audio: return audioURL
        case .video: return videoURL
        }
    }

    /// Plans a user-initiated `switchMediaKind(to:)` call. Returns nil when the episode has no
    /// enclosure of the requested kind - callers should only ever offer the switch when the
    /// target kind is available, but this guards against a stale/racy call rather than crashing
    /// or silently loading a blank player.
    static func switchPlan(
        to kind: MediaKind,
        audioURL: String?,
        videoURL: String?,
        currentTime: TimeInterval,
        isPlaying: Bool,
        playbackRate: Float
    ) -> MediaSwitchPlan? {
        guard let urlString = urlString(for: kind, audioURL: audioURL, videoURL: videoURL) else {
            return nil
        }
        // Position carries over in seconds as-is, not proportionally - video and audio cuts of
        // the same episode aren't expected to be the same length (see VIDEO_PLAYBACK_PLAN.md).
        return MediaSwitchPlan(
            kind: kind,
            urlString: urlString,
            seekTo: currentTime,
            shouldAutoplay: isPlaying,
            playbackRate: playbackRate
        )
    }

    /// The enclosure URL to download for an episode - whichever kind resolves as the episode's
    /// default (see resolvedDefaultKind). Downloads are one file per episode
    /// (Episode.downloadedFilename), so there's a single URL to pick; defaulting to the same
    /// kind playback would pick keeps "download" and "stream without downloading" consistent,
    /// and (unlike only ever looking at audioURL) doesn't silently no-op for a video-only
    /// episode.
    static func downloadURLString(defaultMediaKind: MediaKind?, audioURL: String?, videoURL: String?) -> String? {
        let kind = resolvedDefaultKind(defaultMediaKind: defaultMediaKind, hasAudioURL: audioURL != nil)
        return urlString(for: kind, audioURL: audioURL, videoURL: videoURL)
    }

    /// Whether a downloaded local file should be used for the given kind - true only when kind
    /// matches whatever was actually downloaded (always the resolved default kind; see
    /// downloadURLString above). Guards against handing e.g. a mixed episode's downloaded audio
    /// file to a video surface after the user explicitly switches that episode to video.
    static func shouldUseLocalFile(requestedKind: MediaKind, defaultMediaKind: MediaKind?, hasAudioURL: Bool) -> Bool {
        requestedKind == resolvedDefaultKind(defaultMediaKind: defaultMediaKind, hasAudioURL: hasAudioURL)
    }
}

struct MediaSwitchPlan: Equatable {
    let kind: MediaKind
    let urlString: String
    let seekTo: TimeInterval
    let shouldAutoplay: Bool
    let playbackRate: Float
}
