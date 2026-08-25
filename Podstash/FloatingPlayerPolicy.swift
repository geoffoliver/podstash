//
//  FloatingPlayerPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic for the floating mini-player bar (iOS card / macOS pill), pulled out so
/// it's testable without SwiftUI.
enum FloatingPlayerPolicy {
    /// Whether the bar's transport controls should respond to interaction. The bar itself is
    /// always shown (as a disabled "Nothing Playing" placeholder) rather than disappearing when
    /// there's no current episode - this just governs whether taps/gestures on it do anything.
    static func controlsEnabled(hasCurrentEpisode: Bool) -> Bool {
        hasCurrentEpisode
    }

    /// Bottom margin for the floating bar. When the refresh status bar is showing, the floating
    /// bar needs to clear it (plus a gap) rather than overlapping it; otherwise it just sits
    /// `baseMargin` above its container's edge.
    static func bottomMargin(baseMargin: CGFloat, gap: CGFloat, refreshBarVisible: Bool, refreshBarHeight: CGFloat) -> CGFloat {
        guard refreshBarVisible else { return baseMargin }
        return baseMargin + refreshBarHeight + gap
    }
}
