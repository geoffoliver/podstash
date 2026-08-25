//
//  OrderedFallbackParserTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("OrderedFallbackParser")
struct OrderedFallbackParserTests {

    @Test("Tries candidates in order and returns the first successful result")
    func triesInOrderOnFirstCall() {
        var parser = OrderedFallbackParser<String, Int>(parsers: [
            { _ in nil },
            { Int($0) },
            { _ in 999 }, // would also match, but index 1 should win first
        ])
        #expect(parser.parse("42") == 42)
    }

    @Test("Returns nil when no candidate matches")
    func returnsNilWhenNothingMatches() {
        var parser = OrderedFallbackParser<String, Int>(parsers: [
            { _ in nil },
            { _ in nil },
        ])
        #expect(parser.parse("not a number") == nil)
    }

    @Test("After a candidate succeeds, subsequent calls try it first without touching earlier candidates")
    func remembersWinningCandidate() {
        var earlierCandidateCallCount = 0
        var parser = OrderedFallbackParser<String, Int>(parsers: [
            { _ in earlierCandidateCallCount += 1; return nil },
            { Int($0) },
        ])

        _ = parser.parse("1") // index 0 fails, index 1 succeeds - remembers index 1
        #expect(earlierCandidateCallCount == 1)

        _ = parser.parse("2") // should try index 1 first now, skipping index 0 entirely
        #expect(earlierCandidateCallCount == 1)
    }

    @Test("Falls back to a full scan when the remembered candidate stops matching")
    func fallsBackWhenRememberedCandidateFails() {
        var parser = OrderedFallbackParser<String, Int>(parsers: [
            { Int($0) },
            { $0 == "special" ? 7 : nil },
        ])

        #expect(parser.parse("1") == 1) // remembers index 0
        #expect(parser.parse("special") == 7) // index 0 fails this time, falls back to index 1
        #expect(parser.parse("2") == 2) // remembers index 0 again
    }
}
