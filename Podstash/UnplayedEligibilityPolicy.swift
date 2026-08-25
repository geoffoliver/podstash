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

    /// Advances a podcast's "most recently played" watermark - monotonic, like
    /// `Podcast.newestKnownPublishDate`, so marking an older episode unplayed again doesn't roll
    /// this back.
    static func advancedMostRecentlyPlayedDate(current: Date?, newlyPlayedDate: Date) -> Date {
        max(current ?? .distantPast, newlyPlayedDate)
    }
}
