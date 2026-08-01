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
    
    /// Unsubscribe from a podcast, deleting all of its data: episodes, playback
    /// state, and any downloaded audio files on disk.
    /// - Returns: true if the unsubscribe was actually persisted to the store.
    @discardableResult
    func unsubscribe(podcast: Podcast) -> Bool {
        unsubscribe(podcasts: [podcast])
    }

    /// Unsubscribe from multiple podcasts in a single save.
    /// - Returns: true if the unsubscribe was actually persisted to the store.
    @discardableResult
    func unsubscribe(podcasts: [Podcast]) -> Bool {
        for podcast in podcasts {
            for episode in podcast.episodes {
                if let downloadedFileURLString = episode.downloadedFileURL,
                   let downloadedFileURL = URL(string: downloadedFileURLString) {
                    try? FileManager.default.removeItem(at: downloadedFileURL)
                }
            }
            modelContext.delete(podcast)
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
