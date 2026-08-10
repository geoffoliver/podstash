//
//  PlaybackProgress.swift
//  Podstash
//

import Foundation
import Combine

/// The part of playback state that changes on every tick during playback - currentTime updates
/// roughly once a second while something is playing (see AudioPlayerManager.setupTimeObserver).
/// Deliberately a separate ObservableObject from AudioPlayerManager itself: SwiftUI's
/// @EnvironmentObject/@ObservedObject subscription is all-or-nothing per object, not per
/// property, so any view holding AudioPlayerManager directly re-renders on every one of its
/// @Published changes - including this one - regardless of whether that view's body actually
/// reads currentTime/duration/playbackRate. Only the views that render live progress
/// (TransportControlsBar, NowPlayingView, CompactPlayerBar, MiniPlayerWindow) hold this object;
/// everything else (sidebar, queue, podcast/episode detail) holds AudioPlayerManager itself for
/// currentEpisode/isPlaying, which only change on user actions, not once a second.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    // Measured height of CompactPlayerBar (iOS), so scrollable lists placed underneath it via
    // NavigationSplitView can reserve enough bottom content inset to fully clear it - the
    // safeAreaInset applied around the NavigationSplitView doesn't propagate into a detail
    // column's List content inset (NavigationSplitView manages its own column safe areas).
    @Published var compactPlayerBarHeight: CGFloat = 0
}
