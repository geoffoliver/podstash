//
//  VideoPlayerWindow.swift
//  Podstash
//

#if os(macOS)
import AppKit
import AVKit

/// Standalone QuickTime-style video window, mirroring MiniPlayerWindowController's shape but
/// hosting AppKit's AVPlayerView instead of hand-rolled controls - it supplies the transport
/// bar, volume, scrubbing, and fullscreen for free. See VIDEO_PLAYBACK_PLAN.md Phase 4.
class VideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    private weak var audioPlayer: AudioPlayerManager?

    convenience init(audioPlayer: AudioPlayerManager) {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = audioPlayer.currentEpisode?.title ?? "Video"
        window.minSize = NSSize(width: 320, height: 200)

        let playerView = AVPlayerView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        playerView.player = audioPlayer.playerForVideoSurface
        playerView.controlsStyle = .floating
        playerView.autoresizingMask = [.width, .height]
        window.contentView = playerView

        self.init(window: window)
        self.audioPlayer = audioPlayer
        window.delegate = self

        // Double-click to enter/exit fullscreen, same as QuickTime Player - the window is
        // already fullscreen-eligible (AVPlayerView's own fullscreen button already puts it into
        // window-level fullscreen), this just adds the double-click shortcut on top.
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        playerView.addGestureRecognizer(doubleClick)
    }

    // The main window is deliberately left alone here (unlike the mini player) - opening the
    // video window is closer to a QuickTime/iTunes video window than a companion mini player.
    func windowWillClose(_ notification: Notification) {
        audioPlayer?.handleVideoWindowClosed()
    }

    @objc private func handleDoubleClick() {
        window?.toggleFullScreen(nil)
    }
}
#endif
