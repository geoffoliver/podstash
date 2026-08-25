//
//  AutoRefreshManager.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftData
import Combine

class AutoRefreshManager: ObservableObject {
    private var refreshTimer: Timer?
    private let settings: AppSettings
    private let refreshCoordinator: RefreshCoordinator
    
    init(settings: AppSettings, refreshCoordinator: RefreshCoordinator) {
        self.settings = settings
        self.refreshCoordinator = refreshCoordinator
    }
    
    func startAutoRefresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            self.stopAutoRefresh() // Clear any existing timer

            guard let interval = self.settings.refreshIntervalEnum.timeInterval else {
                // Manual refresh only
                return
            }

            // Create repeating timer
            self.refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.performScheduledRefresh()
                }
            }

            // Trigger immediate refresh if auto-refresh on launch is enabled
            if self.settings.autoRefreshOnLaunch {
                await self.performScheduledRefresh()
            }
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func performScheduledRefresh() async {
        // Check if we should refresh (e.g., Wi-Fi only setting)
        guard shouldRefreshNow() else {
            return
        }
        
        refreshCoordinator.refreshAllFeeds()
    }
    
    private func shouldRefreshNow() -> Bool {
        // If refresh only on Wi-Fi is enabled, check network status
        if settings.refreshOnlyOnWiFi {
            // TODO: Add network reachability check
            // For now, we'll assume it's okay to refresh
            return true
        }
        
        return true
    }
    
    func updateRefreshInterval() {
        // Restart timer with new interval
        startAutoRefresh()
    }
}
