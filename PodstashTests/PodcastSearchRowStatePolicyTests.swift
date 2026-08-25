//
//  PodcastSearchRowStatePolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("PodcastSearchRowStatePolicy")
struct PodcastSearchRowStatePolicyTests {

    @Test("A feed URL not yet subscribed, and not mid add/remove, is notSubscribed")
    func notSubscribedByDefault() {
        let state = PodcastSearchRowStatePolicy.state(
            forFeedURL: "https://example.com/feed.xml",
            subscribedFeedURLs: [],
            addingFeedURL: nil,
            removingFeedURL: nil
        )
        #expect(state == .notSubscribed)
    }

    @Test("A feed URL matching addingFeedURL is adding")
    func addingWhenAddingFeedURLMatches() {
        let state = PodcastSearchRowStatePolicy.state(
            forFeedURL: "https://example.com/feed.xml",
            subscribedFeedURLs: [],
            addingFeedURL: "https://example.com/feed.xml",
            removingFeedURL: nil
        )
        #expect(state == .adding)
    }

    @Test("A feed URL in subscribedFeedURLs, not mid removal, is subscribed")
    func subscribedWhenInSubscribedSet() {
        let state = PodcastSearchRowStatePolicy.state(
            forFeedURL: "https://example.com/feed.xml",
            subscribedFeedURLs: ["https://example.com/feed.xml"],
            addingFeedURL: nil,
            removingFeedURL: nil
        )
        #expect(state == .subscribed)
    }

    @Test("A feed URL matching removingFeedURL is removing")
    func removingWhenRemovingFeedURLMatches() {
        let state = PodcastSearchRowStatePolicy.state(
            forFeedURL: "https://example.com/feed.xml",
            subscribedFeedURLs: ["https://example.com/feed.xml"],
            addingFeedURL: nil,
            removingFeedURL: "https://example.com/feed.xml"
        )
        #expect(state == .removing)
    }

    @Test("addingFeedURL takes priority over an already-subscribed match")
    func addingTakesPriorityOverSubscribed() {
        let state = PodcastSearchRowStatePolicy.state(
            forFeedURL: "https://example.com/feed.xml",
            subscribedFeedURLs: ["https://example.com/feed.xml"],
            addingFeedURL: "https://example.com/feed.xml",
            removingFeedURL: nil
        )
        #expect(state == .adding)
    }

    @Test("A non-matching addingFeedURL/removingFeedURL for a different row doesn't affect this one")
    func otherRowsInFlightDoNotAffectThisRow() {
        let state = PodcastSearchRowStatePolicy.state(
            forFeedURL: "https://example.com/feed.xml",
            subscribedFeedURLs: [],
            addingFeedURL: "https://example.com/other.xml",
            removingFeedURL: nil
        )
        #expect(state == .notSubscribed)
    }
}
