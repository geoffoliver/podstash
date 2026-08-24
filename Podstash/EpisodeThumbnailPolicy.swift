//
//  EpisodeThumbnailPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic backing `EpisodeThumbnail`, pulled out so it's testable without SwiftUI.
/// See VIDEO_PLAYBACK_PLAN.md Phase 3.
enum EpisodeThumbnailPolicy {
    /// Episode-specific artwork wins over the podcast's artwork when both are present - the same
    /// precedence every call site already used before this was centralized.
    static func resolvedArtworkURLString(episodeArtworkURL: String?, podcastArtworkURL: String?) -> String? {
        episodeArtworkURL ?? podcastArtworkURL
    }

    /// The video badge signals "this episode has a video enclosure available", independent of
    /// which enclosure (audio/video) is the default or currently playing.
    static func showsVideoBadge(videoURL: String?) -> Bool {
        videoURL != nil
    }
}
