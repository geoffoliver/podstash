//
//  RefreshCoordinator.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class RefreshCoordinator: ObservableObject {
    @Published var isRefreshing: Bool = false
    @Published var currentPodcastTitle: String?
    @Published var progress: (current: Int, total: Int)?
    @Published var refreshCompleted: String?
    // Measured height of RefreshStatusBar when it's showing, on iOS only - NavigationSplitView's
    // detail column doesn't shrink in response to a `.safeAreaInset` applied around the whole
    // split view (same quirk as reservePlayerBarSpace), so FloatingPlayerBar there needs this to
    // explicitly clear it rather than relying on layout to keep them apart.
    @Published var statusBarHeight: CGFloat = 0

    private var modelContext: ModelContext?
    private var settings: AppSettings?
    private var downloadManager: DownloadManager?
    private var refreshTask: Task<Void, Never>?
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func setSettings(_ settings: AppSettings) {
        self.settings = settings
    }
    
    func setDownloadManager(_ downloadManager: DownloadManager) {
        self.downloadManager = downloadManager
    }
    
    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        currentPodcastTitle = nil
        progress = nil
        refreshCompleted = "Refresh cancelled."
        
        // Auto-clear after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            if refreshCompleted == "Refresh cancelled." {
                refreshCompleted = nil
            }
        }
    }
    
    func refreshAllFeeds() {
        guard modelContext != nil, !isRefreshing else { return }
        
        // Cancel any existing refresh first
        refreshTask?.cancel()
        
        refreshTask = Task {
            await performRefresh()
        }
    }
    
    func refreshFeed(for podcast: Podcast) {
        refreshSingleFeed(podcast)
    }
    
    func refreshSingleFeed(_ podcast: Podcast) {
        guard modelContext != nil, !isRefreshing else { return }
        
        refreshTask = Task {
            await performRefresh(for: [podcast])
        }
    }
    
    private func performRefresh(for podcasts: [Podcast]? = nil) async {
        guard let modelContext = modelContext, let settings = settings else { return }
        
        isRefreshing = true
        currentPodcastTitle = nil
        refreshCompleted = nil
        
        let fetcher = FeedFetcher(modelContext: modelContext, settings: settings, downloadManager: downloadManager)
        
        let results: [Podcast: Result<Void, Error>]
        
        if let podcasts = podcasts {
            results = await fetcher.fetchFeeds(for: podcasts) { title, current, total in
                self.currentPodcastTitle = title
                self.progress = (current, total)
            }
        } else {
            results = await fetcher.fetchAllFeeds { title, current, total in
                self.currentPodcastTitle = title
                self.progress = (current, total)
            }
        }
        
        // Check if task was cancelled
        guard !Task.isCancelled else {
            return // Cancellation is already handled by cancelRefresh()
        }

        // Collapse any PlaybackRecords duplicated by a CloudKit sync race before retention
        // policy runs, so cleanup operates on one canonical played/queue state per episode.
        PlaybackRecordStore.deduplicate(in: modelContext)

        // Apply retention/auto-delete settings now that new episodes are in
        EpisodeCleanupManager(modelContext: modelContext, settings: settings).cleanupEpisodes()

        // Calculate results
        let successCount = results.values.filter { result in
            if case .success = result { return true }
            return false
        }.count
        
        let failureCount = results.count - successCount
        
        let message: String
        if failureCount == 0 {
            message = "Successfully refreshed \(successCount) podcast(s)!"
        } else if successCount == 0 {
            message = "Failed to refresh \(failureCount) podcast(s)."
        } else {
            message = "Refreshed \(successCount) podcast(s), \(failureCount) failed."
        }
        
        isRefreshing = false
        currentPodcastTitle = nil
        progress = nil
        refreshCompleted = message
        
        // Auto-clear after 3 seconds
        try? await Task.sleep(for: .seconds(3))
        
        guard !Task.isCancelled else { return }
        refreshCompleted = nil
    }
}
