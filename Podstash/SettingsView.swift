//
//  SettingsView.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var autoRefreshManager: AutoRefreshManager?
    
    var body: some View {
        #if os(macOS)
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            Group {
                if let manager = autoRefreshManager {
                    FeedSettingsView(settings: settings)
                        .environmentObject(manager)
                } else {
                    FeedSettingsView(settings: settings)
                }
            }
            .tabItem {
                Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
            }
            
            EpisodeSettingsView(settings: settings)
                .tabItem {
                    Label("Episodes", systemImage: "list.bullet")
                }
            
            PlaybackSettingsView(settings: settings)
                .tabItem {
                    Label("Playback", systemImage: "play.circle")
                }
            
            SyncSettingsView(settings: settings)
                .tabItem {
                    Label("Sync", systemImage: "icloud")
                }
        }
        .frame(width: 500, height: 400)
        #else
        NavigationStack {
            Form {
                Section("General") {
                    GeneralSettingsView(settings: settings)
                }
                
                Section("Feeds") {
                    if let manager = autoRefreshManager {
                        FeedSettingsView(settings: settings)
                            .environmentObject(manager)
                    } else {
                        FeedSettingsView(settings: settings)
                    }
                }
                
                Section("Episodes") {
                    EpisodeSettingsView(settings: settings)
                }
                
                Section("Playback") {
                    PlaybackSettingsView(settings: settings)
                }
                
                Section("Sync") {
                    SyncSettingsView(settings: settings)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        #endif
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
        Form {
            Toggle("Auto-refresh feeds on launch", isOn: $settings.autoRefreshOnLaunch)
            
            Divider()
            
            Picker("Sidebar icon size", selection: $settings.sidebarIconSize) {
                ForEach(SidebarIconSize.allCases) { size in
                    Text(size.rawValue).tag(size.rawValue)
                }
            }
            
            Toggle("Show artwork in episode lists", isOn: $settings.showArtworkInList)
            
            Toggle("Compact list mode", isOn: $settings.compactListMode)
            
            Divider()
            
            #if os(macOS)
            Toggle("Keep Mini Player always on top", isOn: $settings.miniPlayerAlwaysOnTop)
            
            Divider()
            #endif
            
            Toggle("Notify about new episodes", isOn: $settings.notifyNewEpisodes)
            
            Toggle("Notify when downloads complete", isOn: $settings.notifyDownloadComplete)
            
            Divider()
            
            Button("Reset to Defaults") {
                settings.resetToDefaults()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Feed Settings

struct FeedSettingsView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var autoRefreshManager: AutoRefreshManager
    
    var body: some View {
        Form {
            Picker("Refresh interval", selection: $settings.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.rawValue).tag(interval.rawValue)
                }
            }
            .onChange(of: settings.refreshInterval) { _ in
                // Restart timer with new interval
                autoRefreshManager.updateRefreshInterval()
            }
            
            Toggle("Refresh only on Wi-Fi", isOn: $settings.refreshOnlyOnWiFi)
                .disabled(settings.refreshIntervalEnum == .manual)
            
            if settings.refreshIntervalEnum != .manual {
                Text("Feeds will refresh automatically in the background")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Episode Settings

struct EpisodeSettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @State private var storageInfo: (episodeCount: Int, downloadedCount: Int, estimatedSize: String)?
    @State private var isCleaningUp = false
    
    var body: some View {
        Form {
            Stepper("Download \(settings.maxEpisodesToDownload) most recent episode\(settings.maxEpisodesToDownload == 1 ? "" : "s")", 
                   value: $settings.maxEpisodesToDownload, 
                   in: 1...100)
            
            Text("When refreshing feeds, only the most recent \(settings.maxEpisodesToDownload) episode\(settings.maxEpisodesToDownload == 1 ? "" : "s") will be downloaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Divider()
            
            Picker("Keep episodes", selection: $settings.episodeRetentionPolicy) {
                ForEach(EpisodeRetentionPolicy.allCases) { policy in
                    Text(policy.rawValue).tag(policy.rawValue)
                }
            }
            
            if settings.episodeRetentionPolicyEnum == .mostRecent {
                Stepper("Keep \(settings.episodeRetentionCount) episodes", 
                       value: $settings.episodeRetentionCount, 
                       in: 1...100)
            }
            
            Divider()
            
            Toggle("Auto-delete played episodes", isOn: $settings.autoDeletePlayedEpisodes)
            
            if settings.autoDeletePlayedEpisodes {
                Stepper("Delete after \(settings.autoDeleteAfterDays) days", 
                       value: $settings.autoDeleteAfterDays, 
                       in: 1...30)
            }
            
            Divider()
            
            // Storage Info Display
            if let info = storageInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage")
                        .font(.headline)
                    Text("\(info.episodeCount) episodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(info.downloadedCount) downloaded (\(info.estimatedSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            Button(action: {
                cleanUpNow()
            }) {
                HStack {
                    if isCleaningUp {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isCleaningUp ? "Cleaning Up..." : "Clean Up Episodes Now")
                }
            }
            .disabled(isCleaningUp)
            
            Divider()
            
            Toggle("Auto-download new episodes", isOn: $settings.autoDownloadNewEpisodes)
            
            if settings.autoDownloadNewEpisodes {
                Toggle("Download only on Wi-Fi", isOn: $settings.downloadOnlyOnWiFi)
                
                Picker("Download quality", selection: $settings.downloadQuality) {
                    ForEach(DownloadQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadStorageInfo()
        }
    }
    
    private func loadStorageInfo() {
        let cleanup = EpisodeCleanupManager(modelContext: modelContext, settings: settings)
        storageInfo = cleanup.getStorageInfo()
    }
    
    private func cleanUpNow() {
        isCleaningUp = true
        
        Task {
            let cleanup = EpisodeCleanupManager(modelContext: modelContext, settings: settings)
            cleanup.cleanupEpisodes()
            
            // Reload storage info after cleanup
            await MainActor.run {
                loadStorageInfo()
                isCleaningUp = false
            }
        }
    }
}

// MARK: - Playback Settings

struct PlaybackSettingsView: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
        Form {
            Picker("Default playback speed", selection: $settings.defaultPlaybackSpeed) {
                Text("0.5x").tag(Double(0.5))
                Text("0.75x").tag(Double(0.75))
                Text("1.0x (Normal)").tag(Double(1.0))
                Text("1.25x").tag(Double(1.25))
                Text("1.5x").tag(Double(1.5))
                Text("1.75x").tag(Double(1.75))
                Text("2.0x").tag(Double(2.0))
            }
            
            Toggle("Remember playback speed per podcast", isOn: $settings.rememberPlaybackSpeed)
            
            Divider()
            
            Stepper("Skip forward: \(settings.skipForwardInterval)s", 
                   value: $settings.skipForwardInterval, 
                   in: 5...120, 
                   step: 5)
            
            Stepper("Skip backward: \(settings.skipBackwardInterval)s", 
                   value: $settings.skipBackwardInterval, 
                   in: 5...60, 
                   step: 5)
            
            Divider()
            
            Toggle("Continue playback across devices", isOn: $settings.continuePlaybackAcrossDevices)
                .disabled(!settings.iCloudSyncEnabled)
            
            if !settings.iCloudSyncEnabled {
                Text("Enable iCloud sync to use this feature")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sync Settings

struct SyncSettingsView: View {
    @ObservedObject var settings: AppSettings
    
    var body: some View {
        Form {
            Toggle("Enable iCloud sync", isOn: $settings.iCloudSyncEnabled)
                .disabled(true)

            if settings.iCloudSyncEnabled {
                Toggle("Sync playback progress", isOn: $settings.syncPlaybackProgress)
                    .disabled(true)

                Toggle("Sync subscriptions", isOn: $settings.syncSubscriptions)
                    .disabled(true)
            }

            Text("iCloud sync isn't available in this build yet - it requires a paid Apple Developer Program membership, which this app isn't currently signed with. All data is stored locally on this device for now.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView(settings: AppSettings())
}
