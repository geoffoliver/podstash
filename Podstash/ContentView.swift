//
//  ContentView.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI
import Combine
import SwiftData
import UniformTypeIdentifiers
import AVKit

extension UTType {
    static var opml: UTType {
        UTType(filenameExtension: "opml") ?? .xml
    }
}

struct ContentView: View {
    @EnvironmentObject var opmlCoordinator: OPMLImportCoordinator
    @EnvironmentObject var refreshCoordinator: RefreshCoordinator
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @State private var showingImportProgress = false
    @State private var importCompletedMessage: String?
    @State private var selectedPodcast: Podcast?
    // Defaults to true (not false) so a freshly-created ContentView - e.g. after the macOS
    // main window is closed and reopened, which resets all @State - lands on Queue rather
    // than falling through to the bare NowPlayingView() below. NowPlayingView is the only
    // detail view with no .navigationTitle/.toolbar, and landing there collapsed the
    // NavigationSplitView's unified toolbar, making the sidebar look broken/scrolled up too.
    @State private var showingQueue = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
#if os(macOS)
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                PodcastListView(selectedPodcast: $selectedPodcast, showingQueue: $showingQueue, columnVisibility: $columnVisibility)
            } detail: {
                if let podcast = selectedPodcast, !showingQueue {
                    PodcastDetailView(podcast: podcast)
                        .id(podcast.id) // Force new view when podcast changes
                } else {
                    // Queue is the default/fallback detail view (also covers the case where
                    // a podcast gets deselected without Queue being clicked directly - see
                    // showingQueue's default-true comment above). NowPlayingView is no longer
                    // reachable here now that Queue is the default view; it's still used as
                    // the iOS sheet from CompactPlayerBar.
                    QueueView()
                        .id("queue") // Force refresh when switching to queue
                }
            }
            .frame(minWidth: 700, minHeight: 500)
            
            // Refresh status bar (above transport controls)
            if refreshCoordinator.isRefreshing {
                RefreshStatusBar(
                    currentPodcastTitle: refreshCoordinator.currentPodcastTitle,
                    progress: refreshCoordinator.progress,
                    onCancel: { refreshCoordinator.cancelRefresh() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let message = refreshCoordinator.refreshCompleted {
                // Show completion message in the status bar area
                RefreshStatusBar(
                    completionMessage: message,
                    onDismiss: {
                        withAnimation {
                            refreshCoordinator.refreshCompleted = nil
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Transport controls bar at bottom
            if audioPlayer.currentEpisode != nil {
                TransportControlsBar()
                    .environmentObject(audioPlayer)
            }
        }
        .overlay {
            if showingImportProgress {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView("Importing OPML...")
                                .controlSize(.large)
                            
                            if let currentFeedTitle = opmlCoordinator.currentFeedTitle {
                                VStack(spacing: 4) {
                                    Text("Processing:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(currentFeedTitle)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                }
                            }
                            
                            Button("Cancel Import") {
                                opmlCoordinator.cancelImport()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.red)
                        }
                        .frame(width: 350)
                        .padding(24)
                        .background(.regularMaterial)
                        .cornerRadius(16)
                        .shadow(radius: 20)
                    )
                    .allowsHitTesting(true)
                    .zIndex(999)
            }
        }
        .overlay(alignment: .top) {
            if let message = importCompletedMessage {
                Text(message)
                    .font(.subheadline)
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .onChange(of: opmlCoordinator.isImporting) { _, newValue in showingImportProgress = newValue }
        .onReceive(opmlCoordinator.$importCompleted) { completedMessage in
            guard let completedMessage = completedMessage else { return }
            importCompletedMessage = completedMessage
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    importCompletedMessage = nil
                }
            }
        }
        .onKeyPress(.space) {
            // Toggle play/pause when spacebar is pressed
            if audioPlayer.currentEpisode != nil {
                audioPlayer.togglePlayPause()
                return .handled
            }
            return .ignored
        }
#else
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PodcastListView(selectedPodcast: $selectedPodcast, showingQueue: $showingQueue, columnVisibility: $columnVisibility)
        } detail: {
            if let podcast = selectedPodcast, !showingQueue {
                PodcastDetailView(podcast: podcast)
                    .id(podcast.id) // Force new view when podcast changes
            } else {
                // Queue is the default/fallback detail view here too (see the macOS branch
                // above for why). NowPlayingView is still used as the iPhone sheet from
                // CompactPlayerBar - that path is untouched.
                QueueView()
                    .id("queue") // Force refresh when switching to queue
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // Refresh status bar (above player)
                if refreshCoordinator.isRefreshing {
                    RefreshStatusBar(
                        currentPodcastTitle: refreshCoordinator.currentPodcastTitle,
                        progress: refreshCoordinator.progress,
                        onCancel: { refreshCoordinator.cancelRefresh() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let message = refreshCoordinator.refreshCompleted {
                    // Show completion message in the status bar area
                    RefreshStatusBar(
                        completionMessage: message,
                        onDismiss: {
                            withAnimation {
                                refreshCoordinator.refreshCompleted = nil
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if audioPlayer.currentEpisode != nil {
                    CompactPlayerBar()
                        .environmentObject(audioPlayer)
                }
            }
        }
        .fileImporter(isPresented: $opmlCoordinator.isImporting, allowedContentTypes: [.opml]) { result in
            if case let .success(url) = result {
                Task {
                    await opmlCoordinator.handleImportedFile(url)
                }
            }
        }
        .overlay {
            if showingImportProgress {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView("Importing OPML...")
                                .controlSize(.large)
                            
                            if let currentFeedTitle = opmlCoordinator.currentFeedTitle {
                                VStack(spacing: 4) {
                                    Text("Processing:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(currentFeedTitle)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                }
                            }
                            
                            Button("Cancel Import") {
                                opmlCoordinator.cancelImport()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.red)
                        }
                        .frame(width: 350)
                        .padding(24)
                        .background(.regularMaterial)
                        .cornerRadius(16)
                        .shadow(radius: 20)
                    )
                    .allowsHitTesting(true)
                    .zIndex(999)
            }
        }
        .overlay(alignment: .top) {
            if let message = importCompletedMessage {
                Text(message)
                    .font(.subheadline)
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .onChange(of: opmlCoordinator.isImporting) { _, newValue in showingImportProgress = newValue }
        .onReceive(opmlCoordinator.$importCompleted) { completedMessage in
            guard let completedMessage = completedMessage else { return }
            importCompletedMessage = completedMessage
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    importCompletedMessage = nil
                }
            }
        }
        .onKeyPress(.space) {
            // Toggle play/pause when spacebar is pressed
            if audioPlayer.currentEpisode != nil {
                audioPlayer.togglePlayPause()
                return .handled
            }
            return .ignored
        }
#endif
    }
}

// MARK: - Podcast List View

struct PodcastListView: View {
    @Query(sort: \Podcast.title) private var podcasts: [Podcast]
    // REMOVED: Don't query all episodes just for the count - it causes massive re-renders
    // Instead, we'll fetch the count on-demand when needed for the badge
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var refreshCoordinator: RefreshCoordinator
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var addPodcastCoordinator: AddPodcastCoordinator
    @EnvironmentObject var opmlCoordinator: OPMLImportCoordinator
    @Binding var selectedPodcast: Podcast?
    @Binding var showingQueue: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var showingSettings = false
    @State private var autoRefreshManager: AutoRefreshManager?
    // macOS starts with the Queue row selected to match showingQueue's default of true in
    // ContentView, since both columns are always visible there. iOS starts with no selection
    // so the app opens on the sidebar (podcast list) instead of auto-pushing into the detail
    // column - NavigationSplitView treats a non-empty initial selection as already "tapped"
    // and jumps straight to detail on compact width.
    #if os(macOS)
    @State private var multiSelection = Set<UUID>([Self.queueTag])
    #else
    @State private var multiSelection = Set<UUID>()
    #endif
    @State private var showingUnsubscribeAlert = false
    @FocusState private var isFocused: Bool

    // Sentinel tag so the Queue row participates in the List's real selection mechanism,
    // just like podcast rows do (tagged with their own id). NavigationSplitView only
    // auto-pushes to the detail column on compact width when the sidebar List's actual
    // `selection` binding changes to a genuinely-tagged value - an untagged row's tap
    // gesture alone (e.g. `multiSelection.removeAll()`) doesn't count as a selection.
    private static let queueTag = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // The Queue row is tagged so it participates in real List selection (see queueTag above),
    // but it must never be treated as a podcast for counting/deletion purposes. It's also
    // stripped out of multi-item selections entirely (see onChange(of: multiSelection) below)
    // so Cmd+A / Select All only ever grabs podcasts, never Queue.
    private var selectedPodcastIDs: Set<UUID> {
        multiSelection.subtracting([Self.queueTag])
    }

    var body: some View {
        // Cache the queue count to avoid multiple database queries per render
        let queueCount = fetchQueueCount()
        // Compute downloaded+unplayed counts once via a single lightweight query, instead of
        // letting each PodcastRowView fault in and filter its full episodes relationship
        // (which was materializing the entire library - 20k+ episodes - on every render).
        let downloadedUnplayedCounts = fetchDownloadedUnplayedCounts()

        List(selection: $multiSelection) {
            // Queue section at top
            Section {
                QueueRowView(queueCount: queueCount, iconSize: settings.sidebarIconSizeEnum.points, fontSize: settings.sidebarIconSizeEnum.fontSize)
                    .tag(Self.queueTag)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingQueue = true
                        selectedPodcast = nil
                        multiSelection = [Self.queueTag]
                        #if !os(macOS)
                        columnVisibility = .detailOnly
                        #endif
                    }
            }
            
            // Podcasts section
            Section("Podcasts") {
                if podcasts.isEmpty {
                    Text("No podcasts yet. Add a podcast RSS feed or import an OPML file to get started!")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(podcasts) { podcast in
                        PodcastRowView(podcast: podcast, iconSize: settings.sidebarIconSizeEnum.points, fontSize: settings.sidebarIconSizeEnum.fontSize, downloadedUnplayedCount: downloadedUnplayedCounts[podcast.id] ?? 0)
                            .tag(podcast.id)
                            .contentShape(Rectangle()) // Make entire row tappable
                            .onTapGesture {
                                // Handle selection manually for better control
                                #if os(macOS)
                                // On macOS, check for modifier keys
                                let modifiers = NSEvent.modifierFlags
                                if modifiers.contains(.command) {
                                    // Cmd+click: toggle selection
                                    if multiSelection.contains(podcast.id) {
                                        multiSelection.remove(podcast.id)
                                    } else {
                                        multiSelection.insert(podcast.id)
                                    }
                                } else if modifiers.contains(.shift) {
                                    // Shift+click: range selection
                                    // For now, just add to selection
                                    multiSelection.insert(podcast.id)
                                } else {
                                    // Normal click: single selection and show detail
                                    multiSelection = [podcast.id]
                                    showingQueue = false
                                    selectedPodcast = podcast
                                }
                                #else
                                // iOS: simple tap behavior
                                if multiSelection.count <= 1 {
                                    multiSelection = [podcast.id]
                                    showingQueue = false
                                    selectedPodcast = podcast
                                    columnVisibility = .detailOnly
                                }
                                #endif
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    multiSelection = [podcast.id]
                                    showingUnsubscribeAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                
                                Button {
                                    markAllAsPlayed(for: podcast)
                                } label: {
                                    Image(systemName: "checkmark")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button("Refresh Feed") {
                                    refreshCoordinator.refreshSingleFeed(podcast)
                                }
                                .disabled(selectedPodcastIDs.count > 1)

                                Button("Mark All as Played") {
                                    markAllAsPlayed(for: podcast)
                                }

                                Button("Unsubscribe", role: .destructive) {
                                    if selectedPodcastIDs.count > 1 && selectedPodcastIDs.contains(podcast.id) {
                                        // Keep existing multi-selection
                                        showingUnsubscribeAlert = true
                                    } else {
                                        // Single item context menu
                                        multiSelection = [podcast.id]
                                        showingUnsubscribeAlert = true
                                    }
                                }
                            }
                    }
                }
            }
        }
        #if !os(macOS)
        .reservePlayerBarSpace(audioPlayer)
        #endif
        .navigationTitle("Podcasts")
        .focused($isFocused)
        .onAppear {
            isFocused = true
            if autoRefreshManager == nil {
                autoRefreshManager = AutoRefreshManager(settings: settings, refreshCoordinator: refreshCoordinator)
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Re-establish focus when window becomes key
            isFocused = true
        }
        #endif
        .onChange(of: multiSelection) { _, newSelection in
            // Update selectedPodcast when single selection changes
            if newSelection.count > 1, newSelection.contains(Self.queueTag) {
                // Queue got swept into a multi-item selection (Cmd+A, Shift+click range) -
                // it should only ever be selected on its own via a direct click.
                multiSelection.remove(Self.queueTag)
            } else if newSelection == [Self.queueTag] {
                showingQueue = true
                selectedPodcast = nil
                #if !os(macOS)
                columnVisibility = .detailOnly
                #endif
            } else if newSelection.count == 1,
               let selectedID = newSelection.first,
               let podcast = podcasts.first(where: { $0.id == selectedID }) {
                showingQueue = false
                selectedPodcast = podcast
                #if !os(macOS)
                columnVisibility = .detailOnly
                #endif
            } else if newSelection.isEmpty {
                selectedPodcast = nil
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            if !selectedPodcastIDs.isEmpty {
                showingUnsubscribeAlert = true
            }
        }
        #endif
        .toolbar {
            ToolbarItem {
                Button(action: {
                    refreshCoordinator.refreshAllFeeds()
                }) {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .disabled(refreshCoordinator.isRefreshing)
            }
            
            #if !os(macOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        addPodcastCoordinator.showDialog()
                    } label: {
                        Label("Add Podcast by URL…", systemImage: "plus.circle")
                    }

                    Button {
                        opmlCoordinator.importOPML()
                    } label: {
                        Label("Import OPML…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSettings = true
                }) {
                    Label("Settings", systemImage: "gear")
                }
            }
            #endif
        }
        .alert(selectedPodcastIDs.count == 1 ? "Unsubscribe from Podcast?" : "Unsubscribe from \(selectedPodcastIDs.count) Podcasts?",
               isPresented: $showingUnsubscribeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unsubscribe", role: .destructive) {
                unsubscribeSelected()
            }
        } message: {
            if selectedPodcastIDs.count == 1,
               let selectedID = selectedPodcastIDs.first,
               let podcast = podcasts.first(where: { $0.id == selectedID }) {
                Text("Are you sure you want to unsubscribe from \"\(podcast.title)\"? This will delete all downloaded episodes.")
            } else {
                Text("Are you sure you want to unsubscribe from \(selectedPodcastIDs.count) podcasts? This will delete all downloaded episodes.")
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings, autoRefreshManager: autoRefreshManager)
        }
        #endif
    }
    
    private func unsubscribeSelected() {
        let podcastsToDelete = podcasts.filter { selectedPodcastIDs.contains($0.id) }
        
        // Check if we're deleting a podcast that has the currently playing episode
        if let currentEpisode = audioPlayer.currentEpisode {
            let isDeletingCurrentPodcast = podcastsToDelete.contains { podcast in
                podcast.episodes.contains { $0.id == currentEpisode.id }
            }
            
            if isDeletingCurrentPodcast {
                audioPlayer.stop()
            }
        }
        
        let subscriptionManager = SubscriptionManager(modelContext: modelContext)
        subscriptionManager.unsubscribe(podcasts: podcastsToDelete)

        multiSelection.removeAll()
        selectedPodcast = nil
    }
    
    private func markAllAsPlayed(for podcast: Podcast) {
        for episode in podcast.episodes {
            episode.isPlayed = true
        }
        try? modelContext.save()
    }
    
    private func fetchQueueCount() -> Int {
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.queuePosition != nil && !episode.isPlayed
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Downloaded+unplayed episode counts keyed by podcast ID, computed with one query scoped to
    /// downloaded episodes only (a small subset) rather than faulting in every episode per podcast.
    private func fetchDownloadedUnplayedCounts() -> [UUID: Int] {
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.isDownloaded && !episode.isPlayed
            }
        )
        guard let episodes = try? modelContext.fetch(descriptor) else { return [:] }

        var counts: [UUID: Int] = [:]
        for episode in episodes {
            if let podcastID = episode.podcast?.id {
                counts[podcastID, default: 0] += 1
            }
        }
        return counts
    }
}

extension Color {
    static let lightPurple = Color(red: 0.37254902, green: 0.36470588, blue: 0.71372549)
    static let darkPurple = Color(red: 0.23137255, green: 0.21568627, blue: 0.58431373)
}

struct QueueRowView: View {
    let queueCount: Int
    let iconSize: CGFloat
    let fontSize: CGFloat
    @ScaledMetric(relativeTo: .body) private var dynamicTypeScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 12) {
            // Icon matching the podcast artwork size
            ZStack {
                LinearGradient(
                    colors: [
                        .lightPurple,
                        .darkPurple
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                Image(systemName: "play.house")
                    .font(.system(size: iconSize * 0.6))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            .frame(width: iconSize, height: iconSize)
            .cornerRadius(6)
            
            Text("Queue")
                .font(.system(size: fontSize * dynamicTypeScale))
            
            Spacer()
            
            // Queue count badge
            if queueCount > 0 {
                Text("\(queueCount)")
                    .font(.appFootnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 6)
    }
}

struct PodcastRowView: View {
    let podcast: Podcast
    let iconSize: CGFloat
    let fontSize: CGFloat
    let downloadedUnplayedCount: Int
    @ScaledMetric(relativeTo: .body) private var dynamicTypeScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 12) {
            // Podcast artwork thumbnail
            if let artworkURL = podcast.artworkURL, let url = URL(string: artworkURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    podcastPlaceholder
                }
                .frame(width: iconSize, height: iconSize)
                .cornerRadius(6)
            } else {
                podcastPlaceholder
                    .frame(width: iconSize, height: iconSize)
                    .cornerRadius(6)
            }
            
            Text(podcast.title)
                .font(.system(size: fontSize * dynamicTypeScale))
            
            Spacer()
            
            // Downloaded & unplayed badge
            if downloadedUnplayedCount > 0 {
                Text("\(downloadedUnplayedCount)")
                    .font(.appFootnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 6)
    }

    private var podcastPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "mic.fill")
                .font(.system(size: iconSize * 0.4))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Episode List View

struct EpisodeListView: View {
    let podcast: Podcast
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @State private var episodeForInfoSheet: Episode?

    var body: some View {
        List {
            if podcast.episodes.isEmpty {
                VStack(spacing: 16) {
                    Text("No episodes yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Refresh this podcast to download episodes")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(podcast.episodes.sorted(by: { $0.publishDate > $1.publishDate })) { episode in
                    Button {
                        audioPlayer.play(episode: episode)
                    } label: {
                        EpisodeRowView(episode: episode, onShowInfo: { episodeForInfoSheet = $0 })
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(podcast.title)
        .sheet(item: $episodeForInfoSheet) { episode in
            EpisodeDetailView(episode: episode)
        }
    }
}

struct EpisodeRowView: View {
    let episode: Episode
    let onShowInfo: (Episode) -> Void
    @EnvironmentObject var audioPlayer: AudioPlayerManager

    // Cache stripped description to avoid repeated HTML processing
    private let strippedDescription: String?

    init(episode: Episode, onShowInfo: @escaping (Episode) -> Void) {
        self.episode = episode
        self.onShowInfo = onShowInfo
        self.strippedDescription = episode.episodeDescription?.stripHTMLTags()
    }
    
    var isCurrentlyPlaying: Bool {
        audioPlayer.currentEpisode?.id == episode.id
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(episode.title)
                        .font(.headline)
                        .foregroundStyle(isCurrentlyPlaying ? .blue : .primary)
                    
                    if isCurrentlyPlaying && audioPlayer.isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                
                if let description = strippedDescription {
                    Text(description)
                        .font(.appBody)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack {
                    Text(episode.publishDate, style: .date)
                        .font(.appCaption)
                        .foregroundStyle(.tertiary)

                    if let duration = episode.duration {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(formatDuration(duration))
                            .font(.appCaption)
                            .foregroundStyle(.tertiary)
                    }

                    // Show progress if partially played
                    if episode.playbackPosition > 0 && !episode.isPlayed {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        if let duration = episode.duration, duration > 0 {
                            let percent = Int((episode.playbackPosition / duration) * 100)
                            Text("\(percent)% played")
                                .font(.appCaption)
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Spacer()
                    
                    if episode.isPlayed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
            .padding(.vertical, 4)
            
            // Info button
            Button {
                onShowInfo(episode)
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show episode details")
        }
        .contextMenu {
            Button {
                onShowInfo(episode)
            } label: {
                Label("Show Details", systemImage: "info.circle")
            }
            
            Divider()
            
            Button {
                audioPlayer.play(episode: episode)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            
            if episode.isPlayed {
                Button {
                    episode.isPlayed = false
                } label: {
                    Label("Mark as Unplayed", systemImage: "circle")
                }
            } else {
                Button {
                    episode.isPlayed = true
                } label: {
                    Label("Mark as Played", systemImage: "checkmark.circle.fill")
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Stubs

struct PodcastEpisodeListView: View {
    @Query(sort: \Podcast.title) private var podcasts: [Podcast]
    
    var body: some View {
        List {
            if podcasts.isEmpty {
                Text("No podcasts yet. Import an OPML file to get started!")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(podcasts) { podcast in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(podcast.title)
                            .font(.headline)
                        if let description = podcast.podcastDescription {
                            Text(description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(podcast.feedURL)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Podcasts")
    }
}

#if os(macOS)
private struct AirPlayRoutePickerView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

struct TransportControlsBar: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // Episode artwork thumbnail
                if let episode = audioPlayer.currentEpisode,
                   let podcast = episode.podcast,
                   let artworkURL = podcast.artworkURL,
                   let url = URL(string: artworkURL) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .id(episode.id) // Force image to update when episode changes
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        )
                }
                
                // Episode info
                VStack(alignment: .leading, spacing: 2) {
                    if let episode = audioPlayer.currentEpisode {
                        Text(episode.title)
                            .font(.appSubheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        if let podcast = episode.podcast {
                            Text(podcast.title)
                                .font(.appFootnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: 200, alignment: .leading)

                Spacer()

                // Playback controls
                HStack(spacing: 20) {
                    // Skip backward
                    Button {
                        audioPlayer.skipBackward()
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20))
                            .frame(minWidth: 32, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Skip backward 15 seconds")

                    // Play/Pause
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 40))
                    }
                    .buttonStyle(.plain)
                    .help(audioPlayer.isPlaying ? "Pause" : "Play")

                    // Skip forward
                    Button {
                        audioPlayer.skipForward()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 20))
                            .frame(minWidth: 32, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Skip forward 30 seconds")
                }
                
                Spacer()
                
                // Progress and time
                VStack(spacing: 4) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(
                                    width: geometry.size.width * CGFloat(playbackProgress),
                                    height: 4
                                )
                        }
                        .onTapGesture { location in
                            let progress = location.x / geometry.size.width
                            audioPlayer.seek(to: audioPlayer.duration * Double(progress))
                        }
                    }
                    .frame(height: 4)
                    
                    // Time labels
                    HStack {
                        Text(formatTime(audioPlayer.currentTime))
                            .font(.appCaption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(formatTime(audioPlayer.duration))
                            .font(.appCaption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200)

                // Playback speed menu
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                        Button(action: {
                            audioPlayer.setPlaybackRate(Float(speed))
                        }) {
                            HStack {
                                Text("\(speed, specifier: "%.2f")x")
                                if abs(audioPlayer.playbackRate - Float(speed)) < 0.01 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge")
                        Text("\(audioPlayer.playbackRate, specifier: "%.2f")x")
                    }
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 70)

                AirPlayRoutePickerView()
                    .frame(width: 24, height: 24)
                    .help("AirPlay")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // `duration` starts at 0 and is only populated asynchronously once the
    // player item's duration resolves, so guard against that window to avoid
    // a momentary full-width flash of the progress bar.
    private var playbackProgress: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return min(audioPlayer.currentTime / audioPlayer.duration, 1)
    }
}
#endif

// MARK: - Episode Detail View

struct EpisodeDetailView: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var downloadManager: DownloadManager
    
    var isCurrentlyPlaying: Bool {
        audioPlayer.currentEpisode?.id == episode.id
    }
    
    var body: some View {
        NavigationStack {
            // Plain ScrollView, not List: this sheet is one static block of content (no
            // repeated rows), and wrapping a single row containing a Link in a List makes
            // iOS treat the WHOLE row as the link's tap target - tapping anywhere in the
            // sheet opened the audio file's URL in the browser instead of just the link text.
            ScrollView {
                VStack(spacing: 24) {
                    // Artwork
                    if let artworkURL = episode.artworkURL ?? episode.podcast?.artworkURL,
                       let url = URL(string: artworkURL) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            artworkPlaceholder
                        }
                        .frame(maxWidth: 300, maxHeight: 300)
                        .cornerRadius(16)
                        .shadow(radius: 10)
                    } else {
                        artworkPlaceholder
                            .frame(width: 300, height: 300)
                            .cornerRadius(16)
                            .shadow(radius: 10)
                    }
                    
                    // Episode Info
                    VStack(spacing: 16) {
                        // Title
                        Text(episode.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        // Podcast name
                        if let podcast = episode.podcast {
                            Text(podcast.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Metadata
                        VStack(spacing: 8) {
                            HStack(spacing: 16) {
                                // Publish date
                                Label {
                                    Text(episode.publishDate, style: .date)
                                } icon: {
                                    Image(systemName: "calendar")
                                }
                                .font(.appFootnote)
                                .foregroundStyle(.secondary)

                                // Duration
                                if let duration = episode.duration {
                                    Label {
                                        Text(formatDuration(duration))
                                    } icon: {
                                        Image(systemName: "clock")
                                    }
                                    .font(.appFootnote)
                                    .foregroundStyle(.secondary)
                                }
                            }

                            // Status badges
                            HStack(spacing: 12) {
                                if episode.isDownloaded {
                                    Label("Downloaded", systemImage: "arrow.down.circle.fill")
                                        .font(.appFootnote)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.green)
                                        .cornerRadius(12)
                                }

                                if episode.isPlayed {
                                    Label("Played", systemImage: "checkmark.circle.fill")
                                        .font(.appFootnote)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }

                                if episode.queuePosition != nil {
                                    Label("In Queue", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        .font(.appFootnote)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.orange)
                                        .cornerRadius(12)
                                }
                            }

                            // Progress
                            if episode.playbackPosition > 0 && !episode.isPlayed {
                                if let duration = episode.duration, duration > 0 {
                                    VStack(spacing: 4) {
                                        HStack {
                                            Text("Progress")
                                                .font(.appFootnote)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(Int((episode.playbackPosition / duration) * 100))%")
                                                .font(.appFootnote)
                                                .foregroundStyle(.secondary)
                                        }

                                        // A GeometryReader-based bar relied on List handing
                                        // each row a well-defined width top-down; outside a
                                        // List that proposal can go ambiguous, and the NaN
                                        // width it produced blanked out this entire sheet.
                                        // ProgressView doesn't have that failure mode.
                                        ProgressView(value: episode.playbackPosition, total: duration)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Divider()
                            .padding(.horizontal)
                        
                        // Description
                        if let description = episode.episodeDescription {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.headline)
                                
                                HTMLText(html: description)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                        
                        // Audio URL (for debugging or advanced users)
                        if let url = URL(string: episode.audioURL) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Audio File")
                                    .font(.headline)
                                
                                Link(destination: url) {
                                    HStack {
                                        Image(systemName: "link")
                                        Text(url.lastPathComponent)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    .font(.appBody)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle("Episode Details")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                // .primaryAction implies "the default action of this screen" on macOS, which
                // makes every item inside this overflow Menu inherit the Return key as its
                // shortcut (shown next to each row). This menu isn't a single default action,
                // so use .automatic instead - same trailing position, no inherited shortcut.
                ToolbarItem(placement: .automatic) {
                    Menu {
                        // Play button
                        Button {
                            audioPlayer.play(episode: episode)
                            dismiss()
                        } label: {
                            Label(isCurrentlyPlaying ? "Now Playing" : "Play", systemImage: "play.fill")
                        }
                        
                        Divider()
                        
                        // Download/Delete
                        if episode.isDownloaded {
                            Button(role: .destructive) {
                                downloadManager.deleteDownload(episode)
                            } label: {
                                Label("Delete Download", systemImage: "trash")
                            }
                        } else if downloadManager.isDownloading(episode) {
                            Button(role: .destructive) {
                                downloadManager.cancelDownload(episode)
                            } label: {
                                Label("Cancel Download", systemImage: "xmark.circle")
                            }
                        } else {
                            Button {
                                downloadManager.downloadEpisode(episode)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                        
                        Divider()
                        
                        // Mark as played/unplayed
                        if episode.isPlayed {
                            Button {
                                episode.isPlayed = false
                            } label: {
                                Label("Mark as Unplayed", systemImage: "circle")
                            }
                        } else {
                            Button {
                                episode.isPlayed = true
                            } label: {
                                Label("Mark as Played", systemImage: "checkmark.circle")
                            }
                        }
                        
                        // Add to / Remove from queue
                        if episode.queuePosition != nil {
                            Button {
                                episode.queuePosition = nil
                            } label: {
                                Label("Remove from Queue", systemImage: "minus.circle")
                            }
                        } else {
                            Button {
                                // Add to end of queue
                                let descriptor = FetchDescriptor<Episode>()
                                if let allEpisodes = try? episode.modelContext?.fetch(descriptor) {
                                    let maxPosition = allEpisodes.compactMap { $0.queuePosition }.max() ?? -1
                                    episode.queuePosition = maxPosition + 1
                                }
                            } label: {
                                Label("Add to Queue", systemImage: "text.line.first.and.arrowtriangle.forward")
                            }
                        }
                        
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
#endif
    }
    
    private var artworkPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "waveform")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - HTML Text View

struct HTMLText: View {
    let html: String
    @State private var attributedString: AttributedString?
    // The HTML parser below bakes an explicit font-size into every text run, which
    // bypasses the `.font(.body)` modifier's Dynamic Type scaling entirely. Scaling
    // the baked-in size by this factor keeps the rendered text responsive to the
    // user's text-size setting instead of being permanently pinned at 16px.
    @ScaledMetric(relativeTo: .body) private var dynamicTypeScale: CGFloat = 1.0

    var body: some View {
        Group {
            if let attributedString {
                Text(attributedString)
            } else {
                // Fallback to plain text with HTML stripped, shown until parsing finishes
                Text(html.stripHTMLTags())
            }
        }
        .font(.body)
        .foregroundStyle(.secondary)
        // NSAttributedString's HTML document type parser spins up a hidden WebKit layout
        // pass internally. Calling it synchronously from `body` (as this used to) reenters
        // SwiftUI's render graph mid-evaluation, which produced "AttributeGraph: cycle
        // detected" errors severe enough to blank out the whole screen this view was on.
        // Computing it in a task and publishing the result via @State keeps HTML parsing
        // out of the render graph entirely.
        .task(id: "\(html)|\(dynamicTypeScale)") {
            attributedString = Self.parseHTML(html, scale: dynamicTypeScale)
        }
    }

    private static func parseHTML(_ html: String, scale: CGFloat) -> AttributedString? {
        guard let ns = htmlToAttributedString(html, scale: scale) else { return nil }
        return AttributedString(ns)
    }

    private static func htmlToAttributedString(_ html: String, scale: CGFloat) -> NSAttributedString? {
        // Wrap in a basic HTML document with styling
        let styledHTML =
"""
<html>
<head>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            font-size: \(17 * scale)px;
            line-height: 1.5;
            color: #8e8e93;
        }
        a {
            color: #007AFF;
            text-decoration: none;
        }
        p {
            margin: 0 0 12px 0;
        }
        ul, ol {
            margin: 0 0 12px 0;
            padding-left: 20px;
        }
        li {
            margin-bottom: 4px;
        }
    </style>
</head>
<body>
\(html)
</body>
</html>
"""
        
        guard let data = styledHTML.data(using: .utf8) else { return nil }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }
}

extension String {
    func stripHTMLTags() -> String {
        // Quick check - if no HTML tags, just decode entities
        guard self.contains("<") else {
            return self.decodingBasicHTMLEntities()
        }
        
        // Use regex only when actually displaying to the user (not during parsing)
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodingBasicHTMLEntities()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    ContentView()
}
