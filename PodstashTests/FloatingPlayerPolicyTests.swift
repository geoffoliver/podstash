//
//  FloatingPlayerPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("FloatingPlayerPolicy")
struct FloatingPlayerPolicyTests {

    @Test("Controls are enabled when an episode is loaded")
    func controlsEnabledWithEpisode() {
        #expect(FloatingPlayerPolicy.controlsEnabled(hasCurrentEpisode: true) == true)
    }

    @Test("Controls are disabled when nothing is loaded")
    func controlsDisabledWithoutEpisode() {
        #expect(FloatingPlayerPolicy.controlsEnabled(hasCurrentEpisode: false) == false)
    }

    // MARK: - bottomMargin
    //
    // iOS's RefreshStatusBar is docked via `.safeAreaInset` on the NavigationSplitView, which -
    // per this codebase's documented NavigationSplitView quirk (see reservePlayerBarSpace) -
    // does not shrink the detail column's own rendered frame. So FloatingPlayerBar's `.overlay`
    // inside that column doesn't reposition above it automatically; it must explicitly clear the
    // refresh bar's measured height itself.

    @Test("Uses the base margin when the refresh status bar isn't showing")
    func baseMarginWhenRefreshBarHidden() {
        let margin = FloatingPlayerPolicy.bottomMargin(
            baseMargin: 4,
            gap: 8,
            refreshBarVisible: false,
            refreshBarHeight: 44
        )
        #expect(margin == 4)
    }

    @Test("Clears the refresh status bar plus a gap when it's showing")
    func marginClearsRefreshBarWhenVisible() {
        let margin = FloatingPlayerPolicy.bottomMargin(
            baseMargin: 4,
            gap: 8,
            refreshBarVisible: true,
            refreshBarHeight: 44
        )
        #expect(margin == 56)
    }

    @Test("Ignores a stale refresh bar height when the bar isn't actually visible")
    func ignoresHeightWhenHidden() {
        let margin = FloatingPlayerPolicy.bottomMargin(
            baseMargin: 4,
            gap: 8,
            refreshBarVisible: false,
            refreshBarHeight: 200
        )
        #expect(margin == 4)
    }
}
