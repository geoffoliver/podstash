//
//  PlaybackProgressPolicy.swift
//  Podstash
//

import Foundation

struct ProgressSaveDecision: Equatable {
    let shouldSave: Bool
    let shouldMarkPlayed: Bool
}

/// Pure decision logic for AudioPlayerManager.saveProgress, pulled out so it's testable without
/// AVPlayer. See d300731 (fixed issue with episodes disappearing from queue): using
/// episode.duration - the RSS <itunes:duration> tag - to decide "reached the end" marked episodes
/// played early whenever the feed's stated duration understated the real audio (e.g. dynamically
/// inserted ads not reflected in the feed), silently dropping them from the queue.
enum PlaybackProgressPolicy {
    /// How close to the end (in seconds) counts as "finished" for auto-mark-played purposes.
    static let markPlayedThreshold: TimeInterval = 30
    /// Minimum position delta (in seconds) worth persisting, to avoid SwiftData churn on every tick.
    static let significantChangeThreshold: TimeInterval = 10

    static func decision(
        currentTime: TimeInterval,
        lastSavedPosition: TimeInterval,
        playerMeasuredDuration: TimeInterval,
        episodeDuration: TimeInterval?
    ) -> ProgressSaveDecision {
        let significantChange = abs(currentTime - lastSavedPosition) >= significantChangeThreshold

        // Prefer the AVPlayer-measured duration over the RSS-supplied one - it's the ground
        // truth for how long the actual audio file is, once it's known (0 before the player has
        // loaded it, in which case fall back to the feed's stated duration).
        let effectiveDuration: TimeInterval? = playerMeasuredDuration > 0 ? playerMeasuredDuration : episodeDuration
        let shouldMarkPlayed = effectiveDuration.map { currentTime >= $0 - markPlayedThreshold } ?? false

        return ProgressSaveDecision(shouldSave: significantChange || shouldMarkPlayed, shouldMarkPlayed: shouldMarkPlayed)
    }
}
