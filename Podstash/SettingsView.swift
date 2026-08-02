//
//  SettingsView.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
/// Shared label-column width so every macOS settings tab lines up its controls
/// at the same x position, matching classic Mac preference-pane layout (e.g.
/// Downcast) rather than each tab auto-sizing its own column independently.
private let settingsLabelColumnWidth: CGFloat = 210

/// A "label: control" row for the macOS settings panes. The label is right-aligned
/// in a fixed-width column so rows line up across tabs; leave it empty for a
/// bare checkbox-style control that should still start at the shared column.
private struct SettingsFieldRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .frame(width: settingsLabelColumnWidth, alignment: .trailing)
            control()
            Spacer(minLength: 0)
        }
    }
}

/// A checkbox row: label right-aligned in the shared column, bare checkbox after it.
private struct SettingsCheckboxRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsFieldRow(label: label) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
    }
}

/// Free-form content (buttons, notes) that shouldn't be indented into the label
/// column — left-aligned at the form's margin, matching Downcast's own notes/buttons.
private struct SettingsFreeformRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            Spacer(minLength: 0).frame(width: settingsLabelColumnWidth + 8)
            content()
            Spacer(minLength: 0)
        }
    }
}
#endif

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var autoRefreshManager: AutoRefreshManager?

    var body: some View {
        #if os(macOS)
        TabView {
            VStack(alignment: .leading, spacing: 18) {
                GeneralSettingsView(settings: settings)
            }
            .padding(24)
            .fixedSize(horizontal: false, vertical: true)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            VStack(alignment: .leading, spacing: 18) {
                if let manager = autoRefreshManager {
                    FeedSettingsView(settings: settings)
                        .environmentObject(manager)
                } else {
                    FeedSettingsView(settings: settings)
                }
            }
            .padding(24)
            .fixedSize(horizontal: false, vertical: true)
            .tabItem {
                Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
            }

            VStack(alignment: .leading, spacing: 18) {
                EpisodeSettingsView(settings: settings)
            }
            .padding(24)
            .fixedSize(horizontal: false, vertical: true)
            .tabItem {
                Label("Episodes", systemImage: "list.bullet")
            }

            VStack(alignment: .leading, spacing: 18) {
                PlaybackSettingsView(settings: settings)
            }
            .padding(24)
            .fixedSize(horizontal: false, vertical: true)
            .tabItem {
                Label("Playback", systemImage: "play.circle")
            }
        }
        .frame(width: 560)
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
        #if os(macOS)
        Group {
            SettingsCheckboxRow(label: "Auto-refresh feeds on launch", isOn: $settings.autoRefreshOnLaunch)

            SettingsFieldRow(label: "Sidebar icon size") {
                Picker("", selection: $settings.sidebarIconSize) {
                    ForEach(SidebarIconSize.allCases) { size in
                        Text(size.rawValue).tag(size.rawValue)
                    }
                }
                .labelsHidden()
            }

            SettingsCheckboxRow(label: "Keep Mini Player always on top", isOn: $settings.miniPlayerAlwaysOnTop)

            SettingsFreeformRow {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        #else
        Group {
            Toggle("Auto-refresh feeds on launch", isOn: $settings.autoRefreshOnLaunch)

            Picker("Icon size", selection: $settings.sidebarIconSize) {
                ForEach(SidebarIconSize.allCases) { size in
                    Text(size.rawValue).tag(size.rawValue)
                }
            }

            Button("Reset to Defaults") {
                settings.resetToDefaults()
            }
        }
        #endif
    }
}

// MARK: - Feed Settings

struct FeedSettingsView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var autoRefreshManager: AutoRefreshManager
    @Environment(\.modelContext) private var modelContext

    @State private var exportDocument: OPMLDocument?
    @State private var isExportingOPML = false
    @State private var exportMessage: String?

    var body: some View {
        #if os(macOS)
        Group {
            SettingsFieldRow(label: "Refresh interval") {
                Picker("", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.rawValue).tag(interval.rawValue)
                    }
                }
                .labelsHidden()
                .onChange(of: settings.refreshInterval) { _ in
                    autoRefreshManager.updateRefreshInterval()
                }
            }

            // Tight spacing (rather than the row rhythm's usual 18pt) so the hint reads as a
            // caption attached to the checkbox above it, not its own independent row - the
            // checkbox control's own vertical padding already made the default gap look
            // oversized relative to every other row pairing in this pane.
            VStack(alignment: .leading, spacing: 4) {
                SettingsCheckboxRow(label: "Refresh only on Wi-Fi", isOn: $settings.refreshOnlyOnWiFi)

                if settings.refreshIntervalEnum != .manual {
                    SettingsFreeformRow {
                        Text("Feeds will refresh automatically in the background")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
                .padding(.vertical, 2)

            SettingsFreeformRow {
                Button("Export OPML…") {
                    exportOPML()
                }
            }

            if let exportMessage {
                SettingsFreeformRow {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        #else
        Group {
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

            Button("Export OPML…") {
                exportOPML()
            }

            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fileExporter(isPresented: $isExportingOPML, document: exportDocument, contentType: .opml, defaultFilename: "Podstash") { result in
            switch result {
            case .success:
                showExportMessage("Export complete.")
            case .failure(let error):
                showExportMessage("Export failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    private func exportOPML() {
        let descriptor = FetchDescriptor<Podcast>()
        guard let podcasts = try? modelContext.fetch(descriptor), !podcasts.isEmpty else {
            showExportMessage("No subscriptions to export.")
            return
        }

        #if os(macOS)
        OPMLExporter.presentSavePanel(podcasts: podcasts)
        #else
        exportDocument = OPMLDocument(text: OPMLExporter.generateOPML(from: podcasts))
        isExportingOPML = true
        #endif
    }

    private func showExportMessage(_ message: String) {
        exportMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            exportMessage = nil
        }
    }
}

// MARK: - Episode Settings

struct EpisodeSettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @State private var storageInfo: (episodeCount: Int, downloadedCount: Int, estimatedSize: String)?
    @State private var isCleaningUp = false

    var body: some View {
        #if os(macOS)
        Group {
            SettingsFieldRow(label: "Keep episodes") {
                Picker("", selection: $settings.episodeRetentionPolicy) {
                    ForEach(EpisodeRetentionPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy.rawValue)
                    }
                }
                .labelsHidden()
            }

            if settings.episodeRetentionPolicyEnum == .mostRecent {
                SettingsFieldRow(label: "Episodes to keep") {
                    Stepper("\(settings.episodeRetentionCount) episodes",
                           value: $settings.episodeRetentionCount,
                           in: 1...100)
                }
            }

            if settings.episodeRetentionPolicyEnum == .all {
                SettingsCheckboxRow(label: "Auto-delete played episodes", isOn: $settings.autoDeletePlayedEpisodes)

                if settings.autoDeletePlayedEpisodes {
                    SettingsFieldRow(label: "Delete after") {
                        Stepper("\(settings.autoDeleteAfterDays) days",
                               value: $settings.autoDeleteAfterDays,
                               in: 1...30)
                    }
                }
            }

            if let info = storageInfo {
                SettingsFieldRow(label: "Storage") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(info.episodeCount) episodes")
                        Text("\(info.downloadedCount) downloaded (\(info.estimatedSize))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            SettingsFreeformRow {
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
            }

            SettingsCheckboxRow(label: "Auto-download new episodes", isOn: $settings.autoDownloadNewEpisodes)

            if settings.autoDownloadNewEpisodes {
                SettingsFieldRow(label: "Episodes per refresh") {
                    Stepper("\(settings.maxEpisodesToDownload)",
                           value: $settings.maxEpisodesToDownload,
                           in: 1...100)
                }

                SettingsFreeformRow {
                    Text("When new episodes are found, only the most recent \(settings.maxEpisodesToDownload) episode\(settings.maxEpisodesToDownload == 1 ? "" : "s") will be downloaded automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            loadStorageInfo()
        }
        #else
        Group {
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

            if settings.episodeRetentionPolicyEnum == .all {
                Toggle("Auto-delete played episodes", isOn: $settings.autoDeletePlayedEpisodes)

                if settings.autoDeletePlayedEpisodes {
                    Stepper("Delete after \(settings.autoDeleteAfterDays) days",
                           value: $settings.autoDeleteAfterDays,
                           in: 1...30)
                }
            }

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

            Toggle("Auto-download new episodes", isOn: $settings.autoDownloadNewEpisodes)

            if settings.autoDownloadNewEpisodes {
                Stepper("Download \(settings.maxEpisodesToDownload) most recent episode\(settings.maxEpisodesToDownload == 1 ? "" : "s") per refresh",
                       value: $settings.maxEpisodesToDownload,
                       in: 1...100)

                Text("When new episodes are found, only the most recent \(settings.maxEpisodesToDownload) episode\(settings.maxEpisodesToDownload == 1 ? "" : "s") will be downloaded automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            loadStorageInfo()
        }
        #endif
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
        #if os(macOS)
        Group {
            SettingsFieldRow(label: "Playback speed") {
                Picker("", selection: $settings.defaultPlaybackSpeed) {
                    Text("0.5x").tag(Double(0.5))
                    Text("0.75x").tag(Double(0.75))
                    Text("1.0x (Normal)").tag(Double(1.0))
                    Text("1.25x").tag(Double(1.25))
                    Text("1.5x").tag(Double(1.5))
                    Text("1.75x").tag(Double(1.75))
                    Text("2.0x").tag(Double(2.0))
                }
                .labelsHidden()
            }

            SettingsFieldRow(label: "Skip forward") {
                Stepper("\(settings.skipForwardInterval)s",
                       value: $settings.skipForwardInterval,
                       in: 5...120,
                       step: 5)
            }

            SettingsFieldRow(label: "Skip backward") {
                Stepper("\(settings.skipBackwardInterval)s",
                       value: $settings.skipBackwardInterval,
                       in: 5...60,
                       step: 5)
            }
        }
        #else
        Group {
            Picker("Default playback speed", selection: $settings.defaultPlaybackSpeed) {
                Text("0.5x").tag(Double(0.5))
                Text("0.75x").tag(Double(0.75))
                Text("1.0x (Normal)").tag(Double(1.0))
                Text("1.25x").tag(Double(1.25))
                Text("1.5x").tag(Double(1.5))
                Text("1.75x").tag(Double(1.75))
                Text("2.0x").tag(Double(2.0))
            }

            Stepper("Skip forward: \(settings.skipForwardInterval)s",
                   value: $settings.skipForwardInterval,
                   in: 5...120,
                   step: 5)

            Stepper("Skip backward: \(settings.skipBackwardInterval)s",
                   value: $settings.skipBackwardInterval,
                   in: 5...60,
                   step: 5)
        }
        #endif
    }
}

#Preview {
    SettingsView(settings: AppSettings())
}
