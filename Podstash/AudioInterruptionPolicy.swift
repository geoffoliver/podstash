//
//  AudioInterruptionPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic for AudioPlayerManager's response to AVAudioSession interruptions (phone
/// calls, Siri, Maps turn-by-turn directions, etc.) - pulled out so it's testable without a real
/// AVAudioSession, which only exists on iOS/tvOS/watchOS. See AudioPlayerManager's interruption
/// notification handler for how this is wired up.
enum AudioInterruptionPolicy {
    enum Phase: Equatable {
        /// The interruption has started - something else (Siri, Maps, a call) now owns the
        /// audio session.
        case began
        /// The interruption has ended. `shouldResume` mirrors
        /// `AVAudioSession.InterruptionOptions.shouldResume`, the system's own signal for
        /// whether it's appropriate to resume (false for e.g. an incoming phone call).
        case ended(shouldResume: Bool)
    }

    enum Action: Equatable {
        case pause
        case resume
        case doNothing
    }

    /// - Parameters:
    ///   - wasPlayingBeforeInterruption: whether playback was active right before this
    ///     interruption began - used on `.ended` so we don't resume playback the user had
    ///     already paused themselves before the interruption occurred.
    static func action(for phase: Phase, isPlaying: Bool, wasPlayingBeforeInterruption: Bool) -> Action {
        switch phase {
        case .began:
            return isPlaying ? .pause : .doNothing
        case .ended(let shouldResume):
            return (shouldResume && wasPlayingBeforeInterruption) ? .resume : .doNothing
        }
    }
}
