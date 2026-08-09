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
    @Published var currentEpisode: Episode?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    // Measured height of CompactPlayerBar (iOS), so scrollable lists placed underneath it via
    // NavigationSplitView can reserve enough bottom content inset to fully clear it - the
    // safeAreaInset applied around the NavigationSplitView doesn't propagate into a detail
    // column's List content inset (NavigationSplitView manages its own column safe areas).
    @Published var compactPlayerBarHeight: CGFloat = 0

    // MARK: - Private Properties
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var modelContext: ModelContext?
    private var periodicSaveTimer: Timer?
    private var settings: AppSettings?
    
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
        #endif
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func setSettings(_ settings: AppSettings) {
        self.settings = settings
        
        // Apply default playback speed
        self.playbackRate = Float(settings.defaultPlaybackSpeed)
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
        lastSavedPosition = episode.playbackPosition // Reset the save tracking
        duration = 0 // Reset so the time observer picks up the new episode's duration

        // Clear stale artwork from the previous episode so it doesn't linger until the new one loads
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        let url = localFileURL(for: episode) ?? URL(string: episode.audioURL)
        guard let url else {
            print("Invalid audio URL: \(episode.audioURL)")
            return
        }
        
        // Cleanup old player first
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
        player?.pause()
        player = nil
        
        // Create player
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Set playback rate
        player?.rate = playbackRate
        
        // Seek to saved position
        if episode.playbackPosition > 0 {
            let time = CMTime(seconds: episode.playbackPosition, preferredTimescale: 600)
            player?.seek(to: time)
        }
        
        // Setup observers
        setupTimeObserver()
        setupNotifications()
        
        // Start playing
        player?.play()
        isPlaying = true
        
        // Update last played date
        episode.lastPlayedDate = Date()
        try? modelContext?.save()
        
        // Setup periodic save timer (every 10 seconds)
        setupPeriodicSaveTimer()
        
        // Update Now Playing info
        updateNowPlayingInfo()
        
        // Load artwork once (asynchronously, won't block)
        loadNowPlayingArtwork()
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

    func resume() {
        player?.play()
        // CRITICAL: Force immediate UI update by using objectWillChange
        objectWillChange.send()
        isPlaying = true
        updateNowPlayingInfo()
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
        player?.pause()
        isPlaying = false
        
        // Save progress
        if let episode = currentEpisode {
            saveProgress(for: episode)
        }
        
        // Cleanup
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
        player = nil
        
        currentEpisode = nil
        
        // Clear Now Playing info
        clearNowPlayingInfo()
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] completed in
            guard completed, let self else { return }
            Task { @MainActor in
                self.currentTime = time
                self.updateNowPlayingInfo()
            }
        }
    }
    
    func skip(by seconds: TimeInterval) {
        let newTime = currentTime + seconds
        let clampedTime = max(0, min(newTime, duration))
        seek(to: clampedTime)
    }
    
    func skipForward() {
        let interval = TimeInterval(settings?.skipForwardInterval ?? 30)
        skip(by: interval)
    }
    
    func skipBackward() {
        let interval = TimeInterval(settings?.skipBackwardInterval ?? 15)
        skip(by: -interval)
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
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
        if let podcast = episode.podcast {
            nowPlayingInfo[MPMediaItemPropertyArtist] = podcast.title
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = podcast.title
        }

        // Playback info
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0

        // Artwork is loaded once per episode by loadNowPlayingArtwork() and merged in;
        // preserving the existing dict here (rather than rebuilding from scratch) keeps it.

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // New function to load artwork once when starting playback
    private func loadNowPlayingArtwork() {
        guard let episode = currentEpisode,
              let artworkURL = episode.podcast?.artworkURL,
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
        // CRITICAL FIX: Only save if progress changed significantly (at least 10 seconds)
        // This prevents constant @Query updates in SwiftUI views
        let significantChange = abs(currentTime - lastSavedPosition) >= 10
        
        // Always save when marking as played
        let shouldMarkPlayed = episode.duration != nil && currentTime >= episode.duration! - 30
        
        guard significantChange || shouldMarkPlayed else {
            return // Skip save if progress hasn't changed much
        }
        
        episode.playbackPosition = currentTime
        episode.lastPlayedDate = Date()
        lastSavedPosition = currentTime
        
        // Mark as played if reached within 30 seconds of end
        if shouldMarkPlayed {
            episode.isPlayed = true
            episode.playbackPosition = 0 // Reset position for played episodes
        }
        
        try? modelContext?.save()
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
                if abs(newTime - self.currentTime) >= 0.5 {
                    self.currentTime = newTime

                    // Keep Control Center / lock screen elapsed time in sync while playing
                    if self.isPlaying {
                        self.updateNowPlayingInfo()
                    }
                }

                // Update duration only once, not on every tick
                if self.duration == 0,
                   let duration = self.player?.currentItem?.duration.seconds,
                   !duration.isNaN && !duration.isInfinite {
                    self.duration = duration

                    // Update episode duration if not set
                    if let episode = self.currentEpisode,
                       episode.duration == nil || episode.duration == 0 {
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
            if let episode = currentEpisode {
                episode.isPlayed = true
                episode.playbackPosition = 0
                episode.queuePosition = nil // Remove from queue
                episode.lastPlayedDate = Date()
                try? modelContext?.save()
            }
            
            isPlaying = false
            currentTime = 0
            
            // Auto-play next episode in queue
            playNextInQueue()
        }
    }
    
    private func playNextInQueue() {
        guard let context = modelContext else { return }
        
        // Fetch next queued episode
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.queuePosition != nil && !episode.isPlayed
            },
            sortBy: [SortDescriptor(\.queuePosition)]
        )
        
        if let episodes = try? context.fetch(descriptor),
           let nextEpisode = episodes.first {
            play(episode: nextEpisode)
        }
    }
}
