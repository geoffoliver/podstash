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
        setupRemoteCommands()
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
        guard let url = URL(string: episode.audioURL) else {
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
    }
    
    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func pause() {
        player?.pause()
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
            if completed {
                self?.currentTime = time
                self?.updateNowPlayingInfo()
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
        
        var nowPlayingInfo = [String: Any]()
        
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
        
        // Artwork
        if let artworkURL = episode.podcast?.artworkURL,
           let url = URL(string: artworkURL) {
            // Try to load artwork asynchronously
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = loadImage(from: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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
    
    private func saveProgress(for episode: Episode) {
        episode.playbackPosition = currentTime
        episode.lastPlayedDate = Date()
        
        // Mark as played if reached within 30 seconds of end
        if let duration = episode.duration, currentTime >= duration - 30 {
            episode.isPlayed = true
            episode.playbackPosition = 0 // Reset position for played episodes
        }
        
        try? modelContext?.save()
    }
    
    private func setupPeriodicSaveTimer() {
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self, let episode = self.currentEpisode else { return }
            Task { @MainActor in
                self.saveProgress(for: episode)
            }
        }
    }
    
    // MARK: - Observers
    
    private func setupTimeObserver() {
        // Only setup observer if we're actually playing
        guard player?.currentItem != nil else { return }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // Only update if playing to avoid unnecessary view updates
            guard self.isPlaying else { return }
            
            self.currentTime = time.seconds
            
            // Update duration
            if let duration = self.player?.currentItem?.duration.seconds,
               !duration.isNaN && !duration.isInfinite {
                self.duration = duration
                
                // Update episode duration if not set
                if let episode = self.currentEpisode,
                   episode.duration == nil || episode.duration == 0 {
                    episode.duration = duration
                    try? self.modelContext?.save()
                }
            }
            
            // Update Now Playing info periodically (every 5 seconds to avoid excessive updates)
            let currentSeconds = Int(time.seconds)
            if currentSeconds % 5 == 0 && currentSeconds != Int(self.currentTime) {
                self.updateNowPlayingInfo()
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
