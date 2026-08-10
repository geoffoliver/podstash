//
//  AppSettings.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftUI
import Combine

enum RefreshInterval: String, CaseIterable, Identifiable {
    case hourly = "Every Hour"
    case sixHours = "Every 6 Hours"
    case twelveHours = "Every 12 Hours"
    case daily = "Every 24 Hours"
    case manual = "Manual Only"
    
    var id: String { rawValue }
    
    var timeInterval: TimeInterval? {
        switch self {
        case .hourly: return 3600
        case .sixHours: return 6 * 3600
        case .twelveHours: return 12 * 3600
        case .daily: return 24 * 3600
        case .manual: return nil
        }
    }
}

// rawValue is the persisted UserDefaults value (via @AppStorage) - kept stable independent of
// display wording so changing the user-facing label never silently resets someone's saved
// preference back to the default. See `displayName` for what's actually shown in Settings.
enum EpisodeRetentionPolicy: String, CaseIterable, Identifiable {
    case unplayedOnly = "Unplayed Episodes Only"
    case all = "All Episodes"
    case mostRecent = "Most Recent Episodes"

    var id: String { rawValue }

    // These policies only ever reclaim downloaded audio now, never an episode's local metadata
    // row (see EpisodeCleanupManager) - worded around "downloads" to match.
    var displayName: String {
        switch self {
        case .unplayedOnly: return "Delete Played Downloads"
        case .all: return "Keep All Downloads"
        case .mostRecent: return "Keep Most Recent Downloads"
        }
    }
}

enum SidebarIconSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    
    var id: String { rawValue }
    
    /// Icon size in points. macOS matches Finder's sidebar (16/24/32). iOS shifts
    /// up a full tier: row density that reads fine with a mouse on desktop looks
    /// and feels cramped as a touch target on a phone.
    var points: CGFloat {
        #if os(iOS)
        switch self {
        case .small: return 24
        case .medium: return 32
        case .large: return 40
        }
        #else
        switch self {
        case .small: return 16
        case .medium: return 24
        case .large: return 32
        }
        #endif
    }

    /// Font size for sidebar text. macOS matches Finder's own compact scale;
    /// iOS uses sizes closer to the system's standard list row text.
    var fontSize: CGFloat {
        #if os(iOS)
        switch self {
        case .small: return 17
        case .medium: return 20
        case .large: return 24
        }
        #else
        switch self {
        case .small: return 11
        case .medium: return 13
        case .large: return 15
        }
        #endif
    }
}

class AppSettings: ObservableObject {
    // MARK: - Feed Management
    @AppStorage("refreshInterval") var refreshInterval: String = RefreshInterval.sixHours.rawValue
    @AppStorage("autoRefreshOnLaunch") var autoRefreshOnLaunch: Bool = true
    @AppStorage("refreshOnlyOnWiFi") var refreshOnlyOnWiFi: Bool = true
    
    // MARK: - Episode Management
    @AppStorage("maxEpisodesToDownload") var maxEpisodesToDownload: Int = 1
    @AppStorage("episodeRetentionPolicy") var episodeRetentionPolicy: String = EpisodeRetentionPolicy.unplayedOnly.rawValue
    @AppStorage("episodeRetentionCount") var episodeRetentionCount: Int = 10
    @AppStorage("autoDeletePlayedEpisodes") var autoDeletePlayedEpisodes: Bool = true
    @AppStorage("autoDeleteAfterDays") var autoDeleteAfterDays: Int = 7

    // MARK: - Download Settings
    @AppStorage("autoDownloadNewEpisodes") var autoDownloadNewEpisodes: Bool = true

    // MARK: - Playback Settings
    @AppStorage("defaultPlaybackSpeed") var defaultPlaybackSpeed: Double = 1.0
    @AppStorage("skipForwardInterval") var skipForwardInterval: Int = 30
    @AppStorage("skipBackwardInterval") var skipBackwardInterval: Int = 15
    @AppStorage("continuePlaybackAcrossDevices") var continuePlaybackAcrossDevices: Bool = true

    // MARK: - iCloud Settings
    @AppStorage("iCloudSyncEnabled") var iCloudSyncEnabled: Bool = true

    // MARK: - Appearance
    @AppStorage("sidebarIconSize") var sidebarIconSize: String = SidebarIconSize.medium.rawValue
    @AppStorage("miniPlayerAlwaysOnTop") var miniPlayerAlwaysOnTop: Bool = true
    
    // MARK: - Helper Methods
    
    var refreshIntervalEnum: RefreshInterval {
        RefreshInterval(rawValue: refreshInterval) ?? .sixHours
    }
    
    var episodeRetentionPolicyEnum: EpisodeRetentionPolicy {
        EpisodeRetentionPolicy(rawValue: episodeRetentionPolicy) ?? .unplayedOnly
    }
    
    var sidebarIconSizeEnum: SidebarIconSize {
        SidebarIconSize(rawValue: sidebarIconSize) ?? .medium
    }
    
    func resetToDefaults() {
        refreshInterval = RefreshInterval.sixHours.rawValue
        autoRefreshOnLaunch = true
        refreshOnlyOnWiFi = true
        
        maxEpisodesToDownload = 1
        episodeRetentionPolicy = EpisodeRetentionPolicy.unplayedOnly.rawValue
        episodeRetentionCount = 10
        autoDeletePlayedEpisodes = true
        autoDeleteAfterDays = 7

        autoDownloadNewEpisodes = true

        defaultPlaybackSpeed = 1.0
        skipForwardInterval = 30
        skipBackwardInterval = 15
        continuePlaybackAcrossDevices = true

        iCloudSyncEnabled = true

        sidebarIconSize = SidebarIconSize.medium.rawValue
    }
}
