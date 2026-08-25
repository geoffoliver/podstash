//
//  SkipIntervalPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("SkipIntervalPolicy")
struct SkipIntervalPolicyTests {

    @Test("Uses the user's configured forward interval when set")
    func usesConfiguredForwardInterval() {
        #expect(SkipIntervalPolicy.forwardInterval(configured: 45) == 45)
    }

    @Test("Falls back to 30 seconds forward when nothing is configured")
    func fallsBackToDefaultForwardInterval() {
        #expect(SkipIntervalPolicy.forwardInterval(configured: nil) == 30)
    }

    @Test("Uses the user's configured backward interval when set")
    func usesConfiguredBackwardInterval() {
        #expect(SkipIntervalPolicy.backwardInterval(configured: 10) == 10)
    }

    @Test("Falls back to 15 seconds backward when nothing is configured")
    func fallsBackToDefaultBackwardInterval() {
        #expect(SkipIntervalPolicy.backwardInterval(configured: nil) == 15)
    }
}
