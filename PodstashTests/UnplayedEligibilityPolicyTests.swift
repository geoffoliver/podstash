//
//  UnplayedEligibilityPolicyTests.swift
//  PodstashTests
//

import Testing
import Foundation
@testable import Podstash

@Suite("UnplayedEligibilityPolicy")
struct UnplayedEligibilityPolicyTests {

    // MARK: - isEligible

    @Test("A downloaded, unplayed episode is always eligible, regardless of dates")
    func downloadedUnplayedAlwaysEligible() {
        let eligible = UnplayedEligibilityPolicy.isEligible(
            isDownloaded: true, isPlayed: false,
            publishDate: .distantPast,
            mostRecentlyPlayedDate: .now,
            newestKnownPublishDate: .now
        )
        #expect(eligible == true)
    }

    @Test("A played episode is never eligible, even if downloaded")
    func playedEpisodeNeverEligible() {
        let eligible = UnplayedEligibilityPolicy.isEligible(
            isDownloaded: true, isPlayed: true,
            publishDate: .now,
            mostRecentlyPlayedDate: nil,
            newestKnownPublishDate: .now
        )
        #expect(eligible == false)
    }

    @Test("A non-downloaded episode is eligible when newer than the most recently played episode in its feed")
    func nonDownloadedEligibleWhenNewerThanMostRecentlyPlayed() {
        let mostRecentlyPlayed = Date.now.addingTimeInterval(-1000)
        let eligible = UnplayedEligibilityPolicy.isEligible(
            isDownloaded: false, isPlayed: false,
            publishDate: Date.now.addingTimeInterval(-500),
            mostRecentlyPlayedDate: mostRecentlyPlayed,
            newestKnownPublishDate: .now
        )
        #expect(eligible == true)
    }

    @Test("A non-downloaded episode is not eligible when at or before the most recently played episode")
    func nonDownloadedNotEligibleWhenNotNewerThanMostRecentlyPlayed() {
        let mostRecentlyPlayed = Date.now.addingTimeInterval(-1000)
        let eligibleAtWatermark = UnplayedEligibilityPolicy.isEligible(
            isDownloaded: false, isPlayed: false,
            publishDate: mostRecentlyPlayed,
            mostRecentlyPlayedDate: mostRecentlyPlayed,
            newestKnownPublishDate: .now
        )
        let eligibleBeforeWatermark = UnplayedEligibilityPolicy.isEligible(
            isDownloaded: false, isPlayed: false,
            publishDate: mostRecentlyPlayed.addingTimeInterval(-1),
            mostRecentlyPlayedDate: mostRecentlyPlayed,
            newestKnownPublishDate: .now
        )
        #expect(eligibleAtWatermark == false)
        #expect(eligibleBeforeWatermark == false)
    }

    @Test("With no play history yet in the feed, only the newest known episode is eligible, not the backlog")
    func noPlayHistoryCapsEligibilityToNewestKnownEpisode() {
        let newestKnown = Date.now

        let newestIsEligible = UnplayedEligibilityPolicy.isEligible(
            isDownloaded: false, isPlayed: false,
            publishDate: newestKnown,
            mostRecentlyPlayedDate: nil,
            newestKnownPublishDate: newestKnown
        )
        let olderBacklogItemIsNotEligible = UnplayedEligibilityPolicy.isEligible(
            isDownloaded: false, isPlayed: false,
            publishDate: newestKnown.addingTimeInterval(-86400),
            mostRecentlyPlayedDate: nil,
            newestKnownPublishDate: newestKnown
        )
        #expect(newestIsEligible == true)
        #expect(olderBacklogItemIsNotEligible == false)
    }

    @Test("With no play history and no newest-known date either, a non-downloaded episode is not eligible")
    func noPlayHistoryAndNoWatermarkIsNotEligible() {
        let eligible = UnplayedEligibilityPolicy.isEligible(
            isDownloaded: false, isPlayed: false,
            publishDate: .now,
            mostRecentlyPlayedDate: nil,
            newestKnownPublishDate: nil
        )
        #expect(eligible == false)
    }

    // MARK: - earliestEligibilityThreshold

    @Test("earliestEligibilityThreshold is nil when there are no thresholds at all")
    func earliestThresholdNilWhenEmpty() {
        #expect(UnplayedEligibilityPolicy.earliestEligibilityThreshold([]) == nil)
    }

    @Test("earliestEligibilityThreshold is nil when every podcast has no threshold yet")
    func earliestThresholdNilWhenAllNil() {
        #expect(UnplayedEligibilityPolicy.earliestEligibilityThreshold([nil, nil]) == nil)
    }

    @Test("earliestEligibilityThreshold is the minimum of the non-nil thresholds, ignoring nils")
    func earliestThresholdIsMinimumIgnoringNils() {
        let earliest = Date.now.addingTimeInterval(-2000)
        let middle = Date.now.addingTimeInterval(-1000)
        let latest = Date.now

        let result = UnplayedEligibilityPolicy.earliestEligibilityThreshold([latest, nil, earliest, middle])
        #expect(result == earliest)
    }

    // MARK: - advancedMostRecentlyPlayedDate

    @Test("advancedMostRecentlyPlayedDate adopts the newly played date when there was no prior value")
    func advancesFromNil() {
        let date = Date.now
        let result = UnplayedEligibilityPolicy.advancedMostRecentlyPlayedDate(current: nil, newlyPlayedDate: date)
        #expect(result == date)
    }

    @Test("advancedMostRecentlyPlayedDate advances forward when the newly played date is newer")
    func advancesForward() {
        let current = Date.now.addingTimeInterval(-1000)
        let newlyPlayed = Date.now
        let result = UnplayedEligibilityPolicy.advancedMostRecentlyPlayedDate(current: current, newlyPlayedDate: newlyPlayed)
        #expect(result == newlyPlayed)
    }

    @Test("advancedMostRecentlyPlayedDate does not regress when the newly played date is older")
    func doesNotRegress() {
        let current = Date.now
        let olderReplay = Date.now.addingTimeInterval(-1000)
        let result = UnplayedEligibilityPolicy.advancedMostRecentlyPlayedDate(current: current, newlyPlayedDate: olderReplay)
        #expect(result == current)
    }
}
