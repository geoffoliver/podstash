//
//  PodcastSearchRowStatePolicy.swift
//  Podstash
//

import Foundation

enum PodcastSearchRowState: Equatable {
    case notSubscribed
    case adding
    case subscribed
    case removing
}

enum PodcastSearchRowStatePolicy {
    /// What a Search Podcasts result row should show for a given feed URL, given the set of
    /// currently-subscribed feed URLs and any in-flight add/remove for this dialog.
    static func state(
        forFeedURL feedURL: String,
        subscribedFeedURLs: Set<String>,
        addingFeedURL: String?,
        removingFeedURL: String?
    ) -> PodcastSearchRowState {
        if addingFeedURL == feedURL {
            return .adding
        }
        if removingFeedURL == feedURL {
            return .removing
        }
        if subscribedFeedURLs.contains(feedURL) {
            return .subscribed
        }
        return .notSubscribed
    }
}
