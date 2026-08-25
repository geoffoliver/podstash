//
//  SkipIntervalPolicy.swift
//  Podstash
//

import Foundation

/// Resolves the skip-forward/backward interval AudioPlayerManager actually seeks by, falling
/// back to Apple Podcasts-style defaults when nothing's configured. Pulled out of
/// AudioPlayerManager so UI call sites can't bypass the user's configured interval by hardcoding
/// a literal into `skip(by:)` directly - always go through `skipForward()`/`skipBackward()`.
enum SkipIntervalPolicy {
    static let defaultForwardInterval = 30
    static let defaultBackwardInterval = 15

    static func forwardInterval(configured: Int?) -> TimeInterval {
        TimeInterval(configured ?? defaultForwardInterval)
    }

    static func backwardInterval(configured: Int?) -> TimeInterval {
        TimeInterval(configured ?? defaultBackwardInterval)
    }
}
