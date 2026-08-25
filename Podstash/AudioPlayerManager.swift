//
//  AudioPlayerManager.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import AVFoundation
import Combine
import SwiftData
import MediaPlayer
import SwiftUI

#if os(macOS)
import AppKit
typealias MPImage = NSImage
#else
import UIKit
typealias MPImage = UIImage
#endif

@MainActor
class AudioPlayerManager: ObservableObject {
    // MARK: - Published Properties
    // Only currentEpisode/isPlaying live here - they change on user actions (switch episode,
    // play/pause), not continuously. High-frequency progress ticking lives in the separate
    // `progress` object below (see PlaybackProgress.swift for why the split matters): views
    // that only need "what's playing" (sidebar, queue, podcast/episode detail) hold this object
    // without pulling in progress, so they don't re-render every second something is playing.
    @Published var currentEpisode: Episode?
    @Published var isPlaying: Bool = false
    // Which enclosure is currently loaded. Only ever changes via play(episode:) (resolved from
    // the episode's defaultMediaKind) or switchMediaKind(to:) (explicit user action) - see
    // VIDEO_PLAYBACK_PLAN.md's governing rule.
    @Published var currentMediaKind: MediaKind = .audio

    // Owned, not @Published itself - mutating its own @Published fields doesn't trigger this
    // object's objectWillChange, so holding AudioPlayerManager alone doesn't subscribe you to
    // progress ticks. Views that need live progress hold `progress` directly via a separate
    // environment injection (see PodstashApp.swift).
    let progress = PlaybackProgress()

    // MARK: - Private Properties
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var modelContext: ModelContext?
    private var periodicSaveTimer: Timer?
    private var settings: AppSettings?
    private var podcastDirectory: PodcastDirectory?

    // Episode has no relationship to Podcast (see Models.swift) - resolved via podcastDirectory
    // instead, same as every other call site that used to read `episode.podcast`.
    var currentPodcast: Podcast? {
        guard let currentEpisode else { return nil }
        return podcastDirectory?.podcast(for: currentEpisode.podcastID)
    }
    
    #if os(macOS)
    var miniPlayerController: MiniPlayerWindowController?
    
    func showMiniPlayer() {
        guard let settings = settings else { return }
        
        // If mini player already exists and is visible, just bring it to front
        if let existingWindow = miniPlayerController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        let isNewWindow = miniPlayerController == nil
        
        // Create mini player window if needed
        if miniPlayerController == nil {
            miniPlayerController = MiniPlayerWindowController(audioPlayer: self, settings: settings)
        }
        
        // Batch window operations to minimize menu updates
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        
        // Hide all main windows when showing mini player
        for window in NSApp.windows {
            // Skip the mini player window itself
            if window is SquareMiniPlayerWindow {
                continue
            }
            
            // Hide all other windows (main app windows)
            // Check if it's a main window by verifying it's not a panel, sheet, or utility window
            if window.isVisible && !window.isSheet && window.level == .normal {
                window.orderOut(nil)
            }
        }
        
        // Show mini player
        if let window = miniPlayerController?.window {
            window.makeKeyAndOrderFront(nil)
            
            // Only center if this is a new window with no saved position
            if isNewWindow && UserDefaults.standard.string(forKey: "miniPlayerWindowFrame") == nil {
                window.center()
            }
        }
        
        NSAnimationContext.endGrouping()
    }
    
    func hideMiniPlayer() {
        // Batch window operations to minimize menu updates
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        
        miniPlayerController?.close()
        miniPlayerController = nil
        
        // Restore main window when hiding mini player
        restoreMainWindow()
        
        NSAnimationContext.endGrouping()
    }
    
    private func restoreMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Find and show main window
        for window in NSApp.windows {
            // Skip the mini player window
            if window is SquareMiniPlayerWindow {
                continue
            }

            // Show the first normal-level window we find (the main app window)
            if !window.isVisible && !window.isSheet && window.styleMask.contains(.titled) {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }

    // MARK: - Video Window (Phase 4, see VIDEO_PLAYBACK_PLAN.md)

    var videoPlayerController: VideoPlayerWindowController?

    // Drives the "Open Video" button's visibility (VideoWindowPolicy.showOpenVideoButton needs
    // a reactive read of whether the window is currently open).
    @Published var isVideoWindowOpen: Bool = false

    // Unlike the mini player, the main window is left alone - this is closer to a QuickTime/
    // iTunes video window than a companion mini player.
    func openVideoWindow() {
        guard currentEpisode != nil else { return }
        if let existing = videoPlayerController?.window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        videoPlayerController = VideoPlayerWindowController(audioPlayer: self)
        videoPlayerController?.window?.makeKeyAndOrderFront(nil)
        isVideoWindowOpen = true
    }

    // The "Open Video" button's action: switches the loaded enclosure to video (if available)
    // and opens the window. The only other place besides auto-open (see openVideoWindowIfNeeded)
    // that opens this window - always a direct user action.
    func openVideo() {
        switchMediaKind(to: .video)
        openVideoWindow()
    }

    // Auto-opens the video window when the currently-loaded kind is video and the window isn't
    // already open - covers a video-only episode (nothing to fall back to on Play) and resuming
    // an episode that was left at .video by a prior close with no audio to fall back to.
    private func openVideoWindowIfNeeded() {
        guard VideoWindowPolicy.shouldOpenVideoWindow(mediaKind: currentMediaKind, isWindowOpen: isVideoWindowOpen) else { return }
        openVideoWindow()
    }

    // Called by VideoPlayerWindowController.windowWillClose - the only path that closes this
    // window, whether via the red close button or a future programmatic close. Closing always
    // stops playback entirely (see VideoWindowPolicy.closeAction / VIDEO_PLAYBACK_PLAN.md Phase 4).
    func handleVideoWindowClosed() {
        videoPlayerController = nil
        isVideoWindowOpen = false

        pause()

        guard let episode = currentEpisode else { return }
        if VideoWindowPolicy.closeAction(hasAudioURL: episode.audioURL != nil) == .pauseAndSwitchToAudio {
            switchMediaKind(to: .audio)
        }
    }
    #endif
    
    // MARK: - Initialization
    
    init() {
        configureAudioSession()
        setupRemoteCommands()
    }

    private func configureAudioSession() {
        #if !os(macOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
    }

    #if !os(macOS)
    // Whether playback was active right before the interruption currently in progress began -
    // so .ended doesn't resume playback the user had already paused themselves. Only meaningful
    // between a .began and its matching .ended.
    private var wasPlayingBeforeInterruption = false

    // Handles interruptions from Siri, Maps turn-by-turn directions, phone calls, etc. - without
    // this, the audio session is silently taken over (or handed back) and the transport controls
    // fall out of sync with what's actually audible. See AudioInterruptionPolicy for the pure
    // decision logic this defers to.
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        Task { @MainActor in
            switch type {
            case .began:
                wasPlayingBeforeInterruption = isPlaying
                let action = AudioInterruptionPolicy.action(for: .began, isPlaying: isPlaying, wasPlayingBeforeInterruption: wasPlayingBeforeInterruption)
                if action == .pause {
                    pause()
                }

            case .ended:
                let optionsValue = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
                let action = AudioInterruptionPolicy.action(for: .ended(shouldResume: shouldResume), isPlaying: isPlaying, wasPlayingBeforeInterruption: wasPlayingBeforeInterruption)
                wasPlayingBeforeInterruption = false
                if action == .resume {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    resume()
                }

            @unknown default:
                break
            }
        }
    }
    #endif
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func setSettings(_ settings: AppSettings) {
        self.settings = settings

        // Apply default playback speed
        self.progress.playbackRate = Float(settings.defaultPlaybackSpeed)
    }

    func setPodcastDirectory(_ directory: PodcastDirectory) {
        self.podcastDirectory = directory
    }
    
    deinit {
        // Can't call main actor methods from deinit
        // Cleanup will happen when the class is deinitialized naturally
    }
    
    // MARK: - Playback Control
    
    func play(episode: Episode) {
        // If same episode, just resume
        if currentEpisode?.id == episode.id {
            resume()
            return
        }
        
        // Save current episode progress before switching
        if let current = currentEpisode {
            saveProgress(for: current)
        }
        
        // Setup new episode
        currentEpisode = episode
        let state = modelContext.map { PlaybackRecordStore.state(for: episode, in: $0) } ?? EpisodeState()
        lastSavedPosition = state.playbackPosition // Reset the save tracking
        progress.duration = 0 // Reset so the time observer picks up the new episode's duration

        // Clear stale artwork from the previous episode so it doesn't linger until the new one loads
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        let kind = MediaKindPolicy.resolvedDefaultKind(defaultMediaKind: episode.defaultMediaKind, hasAudioURL: episode.audioURL != nil)
        guard let url = resolvedURL(for: kind, episode: episode) else {
            print("Invalid \(kind) URL for episode: \(episode.title)")
            return
        }
        currentMediaKind = kind
        isVideoFrameVisible = true // a previous episode's "hide the frame" choice never carries over

        // Cleanup old player first
        teardownPlayerItem()
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
        
        // Create player
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Set playback rate
        player?.rate = progress.playbackRate
        
        // Seek to saved position
        if state.playbackPosition > 0 {
            let time = CMTime(seconds: state.playbackPosition, preferredTimescale: 600)
            player?.seek(to: time)
        }
        
        // Setup observers
        setupTimeObserver()
        setupNotifications()
        
        // Start playing
        player?.play()
        isPlaying = true
        
        // Update last played date
        if let modelContext {
            let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext)
            record.lastPlayedDate = Date()
            try? modelContext.save()
        }
        
        // Setup periodic save timer (every 10 seconds)
        setupPeriodicSaveTimer()
        
        // Update Now Playing info
        updateNowPlayingInfo()
        
        // Load artwork once (asynchronously, won't block)
        loadNowPlayingArtwork()

        #if os(macOS)
        openVideoWindowIfNeeded()
        #endif
        updateVideoTrackEnabled()
    }
    
    // Prefer a downloaded local file over streaming, falling back to nil (streaming) if the
    // file is missing so a stale/deleted download doesn't silently break playback.
    private func localFileURL(for episode: Episode) -> URL? {
        guard episode.isDownloaded,
              let filename = episode.downloadedFilename else {
            return nil
        }
        let url = DownloadManager.localFileURL(forStoredFilename: filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    // Resolves the URL to actually load for a given kind: the local download if there is one
    // AND it's actually a download of this kind (downloads are one file per episode, always the
    // resolved default kind - see MediaKindPolicy.shouldUseLocalFile), remote streaming URL
    // otherwise.
    private func resolvedURL(for kind: MediaKind, episode: Episode) -> URL? {
        let urlString = MediaKindPolicy.urlString(for: kind, audioURL: episode.audioURL, videoURL: episode.videoURL)
        let usesLocal = MediaKindPolicy.shouldUseLocalFile(requestedKind: kind, defaultMediaKind: episode.defaultMediaKind, hasAudioURL: episode.audioURL != nil)
        if usesLocal, let local = localFileURL(for: episode) {
            return local
        }
        return urlString.flatMap { URL(string: $0) }
    }

    // Tears down just the AVPlayerItem/player and its time observer - shared by play(episode:)
    // (which also resets the episode-scoped periodicSaveTimer, so that stays out of here) and
    // switchMediaKind(to:) (which doesn't, since the episode itself isn't changing).
    private func teardownPlayerItem() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    // The only other place (besides play(episode:)) allowed to change which enclosure is
    // loaded - always a direct user action (the iOS Audio/Video toggle, or the macOS "Open
    // Video" flow), never foreground/background or window lifecycle. See
    // VIDEO_PLAYBACK_PLAN.md's governing rule.
    func switchMediaKind(to kind: MediaKind) {
        guard let episode = currentEpisode else { return }
        guard let plan = MediaKindPolicy.switchPlan(
            to: kind,
            audioURL: episode.audioURL,
            videoURL: episode.videoURL,
            currentTime: progress.currentTime,
            isPlaying: isPlaying,
            playbackRate: progress.playbackRate
        ) else { return }

        guard let url = resolvedURL(for: plan.kind, episode: episode) else { return }

        teardownPlayerItem()
        progress.duration = 0 // Reset so the time observer re-measures the new enclosure's duration

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        currentMediaKind = plan.kind

        let time = CMTime(seconds: plan.seekTo, preferredTimescale: 600)
        player?.seek(to: time)

        setupTimeObserver()
        setupNotifications()

        // effectiveRate, not an unconditional player?.rate = plan.playbackRate followed by a
        // conditional player?.play() - setting AVPlayer.rate to a nonzero value starts playback
        // immediately, so doing that unconditionally (even briefly, "before" the shouldAutoplay
        // check) started playback regardless of shouldAutoplay. That's what let audio from a
        // closed macOS video window keep playing even though the transport controls correctly
        // showed paused (see VideoWindowPolicy.closeAction - pause() runs first, so isPlaying,
        // and therefore shouldAutoplay, is already false by the time this runs).
        player?.rate = plan.effectiveRate
        isPlaying = plan.shouldAutoplay

        updateNowPlayingInfo()
        updateVideoTrackEnabled()
    }

    // Read-only access to the underlying AVPlayer for video-surface views (AVPlayerView on
    // macOS, an AVPlayerLayer wrapper on iOS - see Phase 4/5) to attach to. This class stays
    // headless otherwise: progress ticking, remote commands, and Now Playing info don't depend
    // on whether anything is actually attached to this.
    var playerForVideoSurface: AVPlayer? { player }

    // Enables/disables the video track of the currently-loaded item without reloading it -
    // cheaper than a full item swap or track reload. Used by iOS background handling (Phase 5)
    // to stop decoding video frames while keeping audio playing, without touching what's loaded
    // or where playback is (no switchMediaKind, no seek).
    func setVideoTrackEnabled(_ enabled: Bool) {
        guard let tracks = player?.currentItem?.tracks else { return }
        for track in tracks where track.assetTrack?.mediaType == .video {
            track.isEnabled = enabled
        }
    }

    // MARK: - iOS video track visibility (Phase 5, see VIDEO_PLAYBACK_PLAN.md)

    // Both default true/false to match reality at launch: the app is active, and no Now Playing
    // surface is visible yet (nothing has requested one). Neither is @Published - nothing reads
    // these directly, they only drive setVideoTrackEnabled via VideoInlinePolicy.
    private var isAppActive: Bool = true
    private var isNowPlayingSurfaceVisible: Bool = false

    // The user's own choice of whether to look at the video frame, independent of
    // currentMediaKind - see VideoDisplayPolicy. Reset to true whenever a new episode starts
    // (play(episode:)) so a previous episode's "hide the frame" choice never carries over.
    // @Published so NowPlayingView's Audio/Video Picker binding can read it directly.
    @Published private(set) var isVideoFrameVisible: Bool = true

    // Called from PodstashApp's scenePhase observer (iOS only).
    func setAppActive(_ active: Bool) {
        isAppActive = active
        updateVideoTrackEnabled()
    }

    // Called from NowPlayingView's video surface appearing/disappearing (iOS only) - covers both
    // the sheet opening/closing and the user swiping it away.
    func setNowPlayingSurfaceVisible(_ visible: Bool) {
        isNowPlayingSurfaceVisible = visible
        updateVideoTrackEnabled()
    }

    // The Audio/Video toggle's action (iOS only) - see VideoDisplayPolicy for why this means
    // different things for a mixed vs. video-only episode.
    func setDisplayMediaKind(_ kind: MediaKind) {
        guard let episode = currentEpisode else { return }
        switch VideoDisplayPolicy.plan(requestedKind: kind, currentMediaKind: currentMediaKind, hasAudioURL: episode.audioURL != nil) {
        case .switchSource(let target):
            switchMediaKind(to: target)
            isVideoFrameVisible = true
        case .setFrameVisible(let visible):
            isVideoFrameVisible = visible
            updateVideoTrackEnabled()
        }
    }

    private func updateVideoTrackEnabled() {
        let enabled = VideoInlinePolicy.shouldEnableVideoTrack(
            mediaKind: currentMediaKind,
            isAppActive: isAppActive,
            isNowPlayingSurfaceVisible: isNowPlayingSurfaceVisible,
            isVideoFrameVisible: isVideoFrameVisible
        )
        setVideoTrackEnabled(enabled)
    }

    func resume() {
        player?.play()
        // CRITICAL: Force immediate UI update by using objectWillChange
        objectWillChange.send()
        isPlaying = true
        updateNowPlayingInfo()

        #if os(macOS)
        // Handles the video-only "closing left mediaKind at .video" case - the next Play
        // naturally reopens the window (see VideoWindowPolicy.closeAction).
        openVideoWindowIfNeeded()
        #endif
    }
    
    func pause() {
        player?.pause()
        // CRITICAL: Force immediate UI update by using objectWillChange
        objectWillChange.send()
        isPlaying = false
        
        // Save progress when pausing
        if let episode = currentEpisode {
            saveProgress(for: episode)
        }
        
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    func stop() {
        isPlaying = false

        // Save progress
        if let episode = currentEpisode {
            saveProgress(for: episode)
        }

        // Cleanup
        teardownPlayerItem()
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil

        currentEpisode = nil
        
        // Clear Now Playing info
        clearNowPlayingInfo()
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] completed in
            guard completed, let self else { return }
            Task { @MainActor in
                self.progress.currentTime = time
                self.updateNowPlayingInfo()
            }
        }
    }

    func skip(by seconds: TimeInterval) {
        let newTime = progress.currentTime + seconds
        let clampedTime = max(0, min(newTime, progress.duration))
        seek(to: clampedTime)
    }
    
    func skipForward() {
        skip(by: SkipIntervalPolicy.forwardInterval(configured: settings?.skipForwardInterval))
    }

    func skipBackward() {
        skip(by: -SkipIntervalPolicy.backwardInterval(configured: settings?.skipBackwardInterval))
    }
    
    func setPlaybackRate(_ rate: Float) {
        progress.playbackRate = rate
        player?.rate = isPlaying ? rate : 0
        updateNowPlayingInfo()
    }
    
    // MARK: - Now Playing Info & Remote Commands
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.resume()
            }
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.pause()
            }
            return .success
        }
        
        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.togglePlayPause()
            }
            return .success
        }
        
        // Skip forward
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.skipForward()
            }
            return .success
        }
        
        // Skip backward
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.skipBackward()
            }
            return .success
        }
        
        // Change playback position
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self.seek(to: event.positionTime)
            }
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else {
            clearNowPlayingInfo()
            return
        }
        
        // Start from existing info so a previously-loaded artwork isn't dropped
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

        // Episode title
        nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title

        // Podcast name as artist/album
        if let podcast = currentPodcast {
            nowPlayingInfo[MPMediaItemPropertyArtist] = podcast.title
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = podcast.title
        }

        // Playback info
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = progress.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress.currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(progress.playbackRate) : 0.0

        // Helps Control Center/lock screen present the right chrome (e.g. a video thumbnail
        // treatment) for video episodes.
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] =
            (currentMediaKind == .video ? MPNowPlayingInfoMediaType.video : MPNowPlayingInfoMediaType.audio).rawValue

        // Artwork is loaded once per episode by loadNowPlayingArtwork() and merged in;
        // preserving the existing dict here (rather than rebuilding from scratch) keeps it.

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // New function to load artwork once when starting playback
    private func loadNowPlayingArtwork() {
        guard currentEpisode != nil,
              let artworkURL = currentPodcast?.artworkURL,
              let url = URL(string: artworkURL) else {
            return
        }
        
        // Try to load artwork asynchronously (only called once per episode)
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = loadImage(from: data) {
                // Update only the artwork in the existing info
                var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
        }
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    private func loadImage(from data: Data) -> MPImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }
    
    // MARK: - Progress Management
    
    private var lastSavedPosition: TimeInterval = 0
    
    private func saveProgress(for episode: Episode) {
        guard let modelContext else { return }

        let decision = PlaybackProgressPolicy.decision(
            currentTime: progress.currentTime,
            lastSavedPosition: lastSavedPosition,
            playerMeasuredDuration: progress.duration,
            episodeDuration: episode.duration
        )

        guard decision.shouldSave else {
            return // Skip save if progress hasn't changed much
        }

        let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext)
        record.playbackPosition = progress.currentTime
        record.lastPlayedDate = Date()
        lastSavedPosition = progress.currentTime

        // Mark as played if reached within markPlayedThreshold seconds of the end
        if decision.shouldMarkPlayed {
            PlaybackRecordStore.markPlayed(episode: episode, in: modelContext)
            record.playbackPosition = 0 // Reset position for played episodes
        }

        try? modelContext.save()
    }
    
    private func setupPeriodicSaveTimer() {
        periodicSaveTimer?.invalidate()
        // CRITICAL FIX: Reduce save frequency from 10s to 30s
        // Saving every 10 seconds is excessive and triggers SwiftData @Query updates
        // We already save on pause, stop, and when episodes finish
        periodicSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let episode = self.currentEpisode else { return }
                self.saveProgress(for: episode)
            }
        }
    }
    
    // MARK: - Observers
    
    private func setupTimeObserver() {
        // Only setup observer if we're actually playing
        guard player?.currentItem != nil else { return }
        
        // CRITICAL FIX: Increase interval to 1 second instead of 0.5 to reduce CPU usage
        // UI updates don't need to be more frequent than once per second
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let newTime = time.seconds

                // CRITICAL FIX: Only publish time updates if they've changed by at least 0.5 seconds
                // This prevents rapid-fire @Published updates that cause view re-rendering
                // Note: We removed the "guard isPlaying" check to ensure currentTime updates
                // even when paused, which helps UI responsiveness for play/pause button state
                if abs(newTime - self.progress.currentTime) >= 0.5 {
                    self.progress.currentTime = newTime

                    // Keep Control Center / lock screen elapsed time in sync while playing
                    if self.isPlaying {
                        self.updateNowPlayingInfo()
                    }
                }

                // Update duration only once, not on every tick
                if self.progress.duration == 0,
                   let duration = self.player?.currentItem?.duration.seconds,
                   !duration.isNaN && !duration.isInfinite {
                    self.progress.duration = duration

                    // Correct episode.duration with the AVPlayer-measured value. This is more
                    // trustworthy than the RSS <itunes:duration> tag it was originally seeded
                    // from, which can be wrong or stale (e.g. dynamic ad insertion), so always
                    // sync it rather than only filling it in when unset.
                    if let episode = self.currentEpisode, episode.duration != duration {
                        episode.duration = duration
                        try? self.modelContext?.save()
                    }
                }
            }
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )
    }
    
    @objc private func playerDidFinishPlaying() {
        Task { @MainActor in
            if let episode = currentEpisode, let modelContext {
                let record = PlaybackRecordStore.markPlayed(episode: episode, in: modelContext)
                record.playbackPosition = 0
                record.queuePosition = nil // Remove from queue
                record.lastPlayedDate = Date()
                try? modelContext.save()
            }

            isPlaying = false
            progress.currentTime = 0

            // Auto-play next episode in queue
            playNextInQueue()
        }
    }

    private func playNextInQueue() {
        guard let context = modelContext else { return }

        // Find the next queued PlaybackRecord, then resolve its local Episode by episodeKey -
        // queue/played state lives on PlaybackRecord, not Episode (see Models.swift).
        let recordDescriptor = FetchDescriptor<PlaybackRecord>(
            predicate: #Predicate { record in
                record.queuePosition != nil && !record.isPlayed
            },
            sortBy: [SortDescriptor(\.queuePosition)]
        )

        guard let records = try? context.fetch(recordDescriptor), let nextRecord = records.first else { return }

        let nextKey = nextRecord.episodeKey
        let episodeDescriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { $0.episodeKey == nextKey }
        )
        if let nextEpisode = (try? context.fetch(episodeDescriptor))?.first {
            play(episode: nextEpisode)
        }
    }
}
