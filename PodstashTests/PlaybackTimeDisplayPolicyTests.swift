//
//  PlaybackTimeDisplayPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("PlaybackTimeDisplayPolicy")
struct PlaybackTimeDisplayPolicyTests {

    @Test("Formats seconds under an hour as m:ss")
    func formatsUnderAnHour() {
        #expect(PlaybackTimeDisplayPolicy.format(65) == "1:05")
    }

    @Test("Formats an hour or more as h:mm:ss")
    func formatsOverAnHour() {
        #expect(PlaybackTimeDisplayPolicy.format(3725) == "1:02:05")
    }

    @Test("Not toggled: elapsed label shows plain current time")
    func elapsedLabelShowsCurrentTimeByDefault() {
        let label = PlaybackTimeDisplayPolicy.elapsedLabel(currentTime: 90, duration: 600, showingRemaining: false)
        #expect(label == "1:30")
    }

    @Test("Toggled: elapsed label shows negative time remaining")
    func elapsedLabelShowsRemainingWhenToggled() {
        let label = PlaybackTimeDisplayPolicy.elapsedLabel(currentTime: 90, duration: 600, showingRemaining: true)
        #expect(label == "-8:30")
    }

    @Test("Toggled and past the known duration: remaining clamps to -0:00 rather than going positive")
    func elapsedLabelClampsWhenPastDuration() {
        let label = PlaybackTimeDisplayPolicy.elapsedLabel(currentTime: 605, duration: 600, showingRemaining: true)
        #expect(label == "-0:00")
    }

    @Test("Toggling twice returns to the original elapsed display")
    func togglingIsReversible() {
        let elapsed = PlaybackTimeDisplayPolicy.elapsedLabel(currentTime: 42, duration: 600, showingRemaining: false)
        let remaining = PlaybackTimeDisplayPolicy.elapsedLabel(currentTime: 42, duration: 600, showingRemaining: true)
        let backToElapsed = PlaybackTimeDisplayPolicy.elapsedLabel(currentTime: 42, duration: 600, showingRemaining: false)
        #expect(elapsed == backToElapsed)
        #expect(elapsed != remaining)
    }
}
