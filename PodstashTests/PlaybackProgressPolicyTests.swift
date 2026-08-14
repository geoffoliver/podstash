//
//  PlaybackProgressPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("PlaybackProgressPolicy")
struct PlaybackProgressPolicyTests {

    @Test("No significant movement and nowhere near the end saves nothing")
    func noChangeNoSave() {
        let decision = PlaybackProgressPolicy.decision(
            currentTime: 100, lastSavedPosition: 95,
            playerMeasuredDuration: 1800, episodeDuration: nil
        )
        #expect(decision.shouldSave == false)
        #expect(decision.shouldMarkPlayed == false)
    }

    @Test("A position change of at least 10 seconds saves, without marking played")
    func significantChangeSavesWithoutMarkingPlayed() {
        let decision = PlaybackProgressPolicy.decision(
            currentTime: 110, lastSavedPosition: 95,
            playerMeasuredDuration: 1800, episodeDuration: nil
        )
        #expect(decision.shouldSave == true)
        #expect(decision.shouldMarkPlayed == false)
    }

    @Test("Regression: a feed-understated episode.duration must not mark played early (d300731)")
    func doesNotMarkPlayedEarlyOnUnderstatedFeedDuration() {
        // The RSS feed says 20 minutes (1200s, ads not accounted for); AVPlayer measured the
        // real file at 30 minutes (1800s). Currently 1180s in - past the OLD buggy threshold
        // (1200 - 30 = 1170) but nowhere near the real end. Must not mark played.
        let decision = PlaybackProgressPolicy.decision(
            currentTime: 1180, lastSavedPosition: 1170,
            playerMeasuredDuration: 1800, episodeDuration: 1200
        )
        #expect(decision.shouldMarkPlayed == false)
    }

    @Test("Marks played within the threshold of the AVPlayer-measured duration")
    func marksPlayedNearRealEnd() {
        let decision = PlaybackProgressPolicy.decision(
            currentTime: 1780, lastSavedPosition: 1770,
            playerMeasuredDuration: 1800, episodeDuration: 1200
        )
        #expect(decision.shouldMarkPlayed == true)
        #expect(decision.shouldSave == true)
    }

    @Test("Falls back to episode.duration when the player hasn't measured one yet")
    func fallsBackToEpisodeDurationBeforePlayerLoads() {
        let decision = PlaybackProgressPolicy.decision(
            currentTime: 580, lastSavedPosition: 570,
            playerMeasuredDuration: 0, episodeDuration: 600
        )
        #expect(decision.shouldMarkPlayed == true)
    }

    @Test("Never marks played when no duration is known from either source")
    func neverMarksPlayedWithoutAnyDuration() {
        let decision = PlaybackProgressPolicy.decision(
            currentTime: 10_000, lastSavedPosition: 0,
            playerMeasuredDuration: 0, episodeDuration: nil
        )
        #expect(decision.shouldMarkPlayed == false)
        #expect(decision.shouldSave == true) // still a significant position change worth saving
    }
}
