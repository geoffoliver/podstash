//
//  VideoPlayerSurface.swift
//  Podstash
//

#if !os(macOS)
import SwiftUI
import AVKit

/// Inline video surface for NowPlayingView on iOS - a thin AVPlayerLayer wrapper rather than
/// SwiftUI's VideoPlayer(player:), which brings its own chrome that would fight the existing
/// custom scrubber/controls stack below it. See VIDEO_PLAYBACK_PLAN.md Phase 5.
struct VideoPlayerSurface: UIViewRepresentable {
    let player: AVPlayer?

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

/// Modal fullscreen presentation for the same player, handed off to AVPlayerViewController for
/// its standard fullscreen transport chrome. Presented via .fullScreenCover from NowPlayingView;
/// dismissing returns to the inline VideoPlayerSurface above.
struct FullscreenVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
#endif
