//
//  SubscriptionManager.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftData

@MainActor
class SubscriptionManager {
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Subscribe to a podcast feed
    /// - Returns: true if successfully subscribed, false if already subscribed or invalid
    func subscribe(title: String, feedURL: String, websiteURL: String? = nil, description: String? = nil) -> Bool {
        // Check if already subscribed
        let descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate { podcast in
                podcast.feedURL == feedURL
            }
        )
        
        if let existingPodcasts = try? modelContext.fetch(descriptor),
           !existingPodcasts.isEmpty {
            // Already subscribed
            return false
        }
        
        // Create new podcast
        let podcast = Podcast(
            title: title,
            feedURL: feedURL,
            websiteURL: websiteURL,
            podcastDescription: description
        )
        
        modelContext.insert(podcast)
        
        do {
            try modelContext.save()
            return true
        } catch {
            print("Error saving podcast: \(error)")
            return false
        }
    }
    
    /// Unsubscribe from a podcast, deleting its local episode metadata, any downloaded audio
    /// files on disk, and its episodes' PlaybackRecord history.
    /// - Returns: true if the unsubscribe was actually persisted to the store.
    @discardableResult
    func unsubscribe(podcast: Podcast) -> Bool {
        unsubscribe(podcasts: [podcast])
    }

    /// Unsubscribe from multiple podcasts in a single save.
    ///
    /// Deletes PlaybackRecord history for the podcasts' episodes too, not just the Episode
    /// metadata rows. PlaybackRecord is keyed only by `episodeKey` (guid ?? audioURL ?? videoURL,
    /// see Models.swift) - not scoped to a particular podcast/feed - and some shows publish
    /// separate audio and video RSS feeds that reuse the same <guid> per episode (it's just a
    /// link to the episode's webpage, not unique to one feed variant). Leaving PlaybackRecord
    /// alone meant unsubscribing from one variant and subscribing to the other silently inherited
    /// the old subscription's played/position state instead of starting fresh.
    ///
    /// This is safe to do unconditionally here because Episode rows are only ever deleted by
    /// unsubscribe itself - EpisodeCleanupManager.cleanupEpisodes only ever reclaims a
    /// downloaded file, never the Episode row - so the episode list fetched below is always the
    /// complete set for this podcast, not a partial one some other cleanup already picked over.
    /// (An earlier version of this method tried to delete PlaybackRecord too, back when that
    /// completeness guarantee didn't hold, and left some records un-cleaned as a result - that
    /// inconsistency is why it was dropped rather than fixed at the time.)
    /// - Returns: true if the unsubscribe was actually persisted to the store.
    @discardableResult
    func unsubscribe(podcasts: [Podcast]) -> Bool {
        var episodeKeysToDelete: Set<String> = []

        for podcast in podcasts {
            let podcastID = podcast.id
            let episodeDescriptor = FetchDescriptor<Episode>(
                predicate: #Predicate { $0.podcastID == podcastID }
            )
            let episodes = (try? modelContext.fetch(episodeDescriptor)) ?? []

            for episode in episodes {
                if let filename = episode.downloadedFilename {
                    try? FileManager.default.removeItem(at: DownloadManager.localFileURL(forStoredFilename: filename))
                }
                episodeKeysToDelete.insert(episode.episodeKey)
                modelContext.delete(episode)
            }

            modelContext.delete(podcast)
        }

        if !episodeKeysToDelete.isEmpty {
            let recordDescriptor = FetchDescriptor<PlaybackRecord>(
                predicate: #Predicate { episodeKeysToDelete.contains($0.episodeKey) }
            )
            let recordsToDelete = (try? modelContext.fetch(recordDescriptor)) ?? []
            for record in recordsToDelete {
                modelContext.delete(record)
            }
        }

        do {
            try modelContext.save()
            return true
        } catch {
            print("Error unsubscribing: \(error)")
            return false
        }
    }
    
    /// Get all subscribed podcasts
    func allPodcasts() -> [Podcast] {
        let descriptor = FetchDescriptor<Podcast>(
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// The feed URL of every currently-subscribed podcast.
    func subscribedFeedURLs() -> Set<String> {
        Set(allPodcasts().map(\.feedURL))
    }

    /// Unsubscribe from whichever podcast is currently subscribed at this feed URL, if any.
    /// - Returns: true if a matching podcast was found and unsubscribed.
    @discardableResult
    func unsubscribe(feedURL: String) -> Bool {
        let descriptor = FetchDescriptor<Podcast>(
            predicate: #Predicate { $0.feedURL == feedURL }
        )
        guard let podcast = (try? modelContext.fetch(descriptor))?.first else { return false }
        return unsubscribe(podcast: podcast)
    }
}
