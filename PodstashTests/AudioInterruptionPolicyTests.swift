//
//  AudioInterruptionPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("AudioInterruptionPolicy")
struct AudioInterruptionPolicyTests {

    // MARK: - began

    @Test("Pauses when an interruption begins while playing (e.g. Siri speaks, Maps gives directions)")
    func pausesOnBeginWhilePlaying() {
        #expect(AudioInterruptionPolicy.action(for: .began, isPlaying: true, wasPlayingBeforeInterruption: false) == .pause)
    }

    @Test("Does nothing on interruption begin if already paused")
    func doesNothingOnBeginWhileAlreadyPaused() {
        #expect(AudioInterruptionPolicy.action(for: .began, isPlaying: false, wasPlayingBeforeInterruption: false) == .doNothing)
    }

    // MARK: - ended

    @Test("Resumes when the interruption ends, the system says resume is possible, and we were playing beforehand")
    func resumesOnEndWhenShouldResumeAndWasPlaying() {
        #expect(AudioInterruptionPolicy.action(for: .ended(shouldResume: true), isPlaying: false, wasPlayingBeforeInterruption: true) == .resume)
    }

    @Test("Does not resume when the interruption ends but the user had paused before it began")
    func doesNotResumeWhenNotPlayingBeforeInterruption() {
        #expect(AudioInterruptionPolicy.action(for: .ended(shouldResume: true), isPlaying: false, wasPlayingBeforeInterruption: false) == .doNothing)
    }

    @Test("Does not resume when the system reports shouldResume is false (e.g. a phone call)")
    func doesNotResumeWhenSystemSaysNo() {
        #expect(AudioInterruptionPolicy.action(for: .ended(shouldResume: false), isPlaying: false, wasPlayingBeforeInterruption: true) == .doNothing)
    }
}
