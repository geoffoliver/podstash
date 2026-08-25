//
//  UnplayedEligibilityPolicy.swift
//  Podstash
//

import Foundation

/// Decides which episodes count as "unplayed" for the Unplayed tab, the sidebar badge, and
/// auto-queueing on refresh - pulled out so it's testable without SwiftData. Beyond the existing
/// "downloaded and unplayed" rule, a non-downloaded episode also counts once it's newer than the
/// most recently played episode in its feed. When a feed has no play history yet, that rule alone
/// would surface the entire back catalog, so it's capped to just the newest known episode until
/// the user has played something.
enum UnplayedEligibilityPolicy {
    static func isEligible(
        isDownloaded: Bool,
        isPlayed: Bool,
        publishDate: Date,
        mostRecentlyPlayedDate: Date?,
        newestKnownPublishDate: Date?
    ) -> Bool {
        guard !isPlayed else { return false }
        if isDownloaded { return true }

        if let mostRecentlyPlayedDate {
            return publishDate > mostRecentlyPlayedDate
        }
        guard let newestKnownPublishDate else { return false }
        return publishDate >= newestKnownPublishDate
    }

    /// The minimum of a set of per-podcast eligibility thresholds (each podcast's
    /// `mostRecentlyPlayedDate ?? newestKnownPublishDate`, or nil if it has neither), ignoring
    /// nils. Lets a caller gathering candidate episodes across many podcasts run one fetch bounded
    /// by `publishDate >= earliestEligibilityThreshold(...)` instead of one bounded fetch per
    /// podcast - each candidate still gets filtered against its own podcast's threshold via
    /// `isEligible` afterward, so widening the fetch bound this way doesn't affect which episodes
    /// end up counted, only how many round trips it takes to gather them. Nil (fetch nothing) only
    /// when every podcast has no threshold yet.
    static func earliestEligibilityThreshold(_ perPodcastThresholds: [Date?]) -> Date? {
        perPodcastThresholds.compactMap { $0 }.min()
    }

    /// Advances a podcast's "most recently played" watermark - monotonic, like
    /// `Podcast.newestKnownPublishDate`, so marking an older episode unplayed again doesn't roll
    /// this back.
    static func advancedMostRecentlyPlayedDate(current: Date?, newlyPlayedDate: Date) -> Date {
        max(current ?? .distantPast, newlyPlayedDate)
    }
}
