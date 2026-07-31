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
    
    /// Unsubscribe from a podcast
    func unsubscribe(podcast: Podcast) {
        modelContext.delete(podcast)
        try? modelContext.save()
    }
    
    /// Get all subscribed podcasts
    func allPodcasts() -> [Podcast] {
        let descriptor = FetchDescriptor<Podcast>(
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
