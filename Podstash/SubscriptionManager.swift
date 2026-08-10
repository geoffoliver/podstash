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
    
    /// Unsubscribe from a podcast, deleting its local episode metadata and any downloaded audio
    /// files on disk.
    /// - Returns: true if the unsubscribe was actually persisted to the store.
    @discardableResult
    func unsubscribe(podcast: Podcast) -> Bool {
        unsubscribe(podcasts: [podcast])
    }

    /// Unsubscribe from multiple podcasts in a single save.
    ///
    /// Deliberately does NOT touch PlaybackRecord: it's durable, cross-device "I've
    /// listened to this" memory, independent of whether you're currently subscribed - if you
    /// resubscribe to the same feed later, previously-played episodes should still show as
    /// played, not look brand new again. (An earlier version of this method tried to delete the
    /// matching PlaybackRecords here, keyed off the podcast's *currently existing* local
    /// episodes - but retention cleanup can have already deleted the episode's downloaded file
    /// by the time you unsubscribe, in the past also deleted the whole row, leaving some
    /// PlaybackRecords silently un-cleaned. That inconsistency, not the persistence itself, was
    /// the bug - so PlaybackRecord just isn't unsubscribe's concern at all now.)
    /// - Returns: true if the unsubscribe was actually persisted to the store.
    @discardableResult
    func unsubscribe(podcasts: [Podcast]) -> Bool {
        var episodeKeysToDequeue: Set<String> = []

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
                episodeKeysToDequeue.insert(episode.episodeKey)
                modelContext.delete(episode)
            }

            modelContext.delete(podcast)
        }

        // A queue entry with no local Episode row left to back it can't actually display -
        // QueueView.queuedEpisodes silently drops any PlaybackRecord it can't join to an Episode -
        // so leaving queuePosition set here just leaves the queue badge counting entries the queue
        // itself will never show. isPlayed/playbackPosition/lastPlayedDate are untouched: that
        // history should still survive a resubscribe (see doc comment above).
        if !episodeKeysToDequeue.isEmpty {
            let recordDescriptor = FetchDescriptor<PlaybackRecord>(
                predicate: #Predicate { episodeKeysToDequeue.contains($0.episodeKey) }
            )
            let recordsToDequeue = (try? modelContext.fetch(recordDescriptor)) ?? []
            for record in recordsToDequeue {
                record.queuePosition = nil
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
}
