//
//  EpisodeCleanupManager.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftData

@MainActor
class EpisodeCleanupManager {
    private let modelContext: ModelContext
    private let settings: AppSettings
    
    init(modelContext: ModelContext, settings: AppSettings) {
        self.modelContext = modelContext
        self.settings = settings
    }
    
    /// Clean up episodes based on retention policy
    func cleanupEpisodes() {
        let policy = settings.episodeRetentionPolicyEnum
        
        switch policy {
        case .all:
            // Keep everything, but check for auto-delete played episodes
            if settings.autoDeletePlayedEpisodes {
                deleteOldPlayedEpisodes()
            }
            
        case .unplayedOnly:
            // Delete all played episodes
            deletePlayedEpisodes()
            
        case .mostRecent:
            // Keep only the most recent X episodes per podcast
            keepMostRecentEpisodes(count: settings.episodeRetentionCount)
        }
        
        try? modelContext.save()
    }
    
    private func deletePlayedEpisodes() {
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.isPlayed
            }
        )
        
        guard let episodes = try? modelContext.fetch(descriptor) else { return }
        
        for episode in episodes {
            modelContext.delete(episode)
        }
    }
    
    private func deleteOldPlayedEpisodes() {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -settings.autoDeleteAfterDays,
            to: Date()
        ) ?? Date()
        
        // Fetch all played episodes
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.isPlayed
            }
        )
        
        guard let episodes = try? modelContext.fetch(descriptor) else { return }
        
        // Filter in Swift instead of predicate (nil coalescing doesn't work in predicates)
        let oldEpisodes = episodes.filter { episode in
            let playedDate = episode.lastPlayedDate ?? Date.distantPast
            return playedDate < cutoffDate
        }
        
        for episode in oldEpisodes {
            // Only delete if downloaded file exists
            if episode.isDownloaded {
                // TODO: Delete actual file from disk
                episode.isDownloaded = false
                episode.downloadedFileURL = nil
            }
            
            // Optionally delete the episode record itself
            modelContext.delete(episode)
        }
    }
    
    private func keepMostRecentEpisodes(count: Int) {
        // Get all podcasts
        let podcastDescriptor = FetchDescriptor<Podcast>()
        guard let podcasts = try? modelContext.fetch(podcastDescriptor) else { return }
        
        for podcast in podcasts {
            // Sort episodes by publish date (newest first)
            let sortedEpisodes = podcast.episodes.sorted { $0.publishDate > $1.publishDate }
            
            // Keep the first 'count' episodes, delete the rest
            let episodesToDelete = Array(sortedEpisodes.dropFirst(count))
            
            for episode in episodesToDelete {
                // Don't delete unplayed episodes unless auto-delete is enabled
                if episode.isPlayed || settings.autoDeletePlayedEpisodes {
                    modelContext.delete(episode)
                }
            }
        }
    }
    
    /// Get storage usage information
    func getStorageInfo() -> (episodeCount: Int, downloadedCount: Int, estimatedSize: String) {
        let descriptor = FetchDescriptor<Episode>()
        guard let episodes = try? modelContext.fetch(descriptor) else {
            return (0, 0, "0 MB")
        }
        
        let downloadedCount = episodes.filter { $0.isDownloaded }.count
        
        // Rough estimate: 1 MB per minute of audio at medium quality
        let totalMinutes = episodes.reduce(0.0) { result, episode in
            if episode.isDownloaded, let duration = episode.duration {
                return result + (duration / 60.0)
            }
            return result
        }
        
        let estimatedMB = Int(totalMinutes)
        let sizeString: String
        if estimatedMB > 1024 {
            sizeString = String(format: "%.1f GB", Double(estimatedMB) / 1024.0)
        } else {
            sizeString = "\(estimatedMB) MB"
        }
        
        return (episodes.count, downloadedCount, sizeString)
    }
}
