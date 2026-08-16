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
    // Scoped @Query, not a plain ad-hoc fetch recomputed inside body: badge counts used to be
    // computed by calling modelContext.fetch(...) directly in `body`, which reran on every
    // single re-render of this view - including every row click, since selecting a row mutates
    // @State right here. That's a synchronous SQL round trip blocking the UI on every click,
    // which is what made the sidebar feel laggy regardless of what was being clicked. These are
    // filtered to just what's downloaded/played/queued (never the full Episode table), so
    // SwiftData only needs to recompute them when matching rows actually change, not on every
    // unrelated render - cheap in-memory work off already-tracked arrays instead of a fresh query.
    @Query(filter: #Predicate<PlaybackRecord> { $0.queuePosition != nil && !$0.isPlayed })
    private var queuedRecords: [PlaybackRecord]
    @Query(filter: #Predicate<Episode> { $0.isDownloaded })
    private var downloadedEpisodesQuery: [Episode]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var refreshCoordinator: RefreshCoordinator
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var addPodcastCoordinator: AddPodcastCoordinator
    @EnvironmentObject var opmlCoordinator: OPMLImportCoordinator
    @EnvironmentObject var podcastSearchCoordinator: PodcastSearchCoordinator
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
    // Podcasts the pending unsubscribe alert will act on. Deliberately separate from
    // multiSelection: writing to multiSelection drives navigation (see onChange below), so
    // swipe/context-menu actions on a podcast that isn't already selected must record their
    // target here instead of via multiSelection, or confirming the alert would race a
    // NavigationSplitView column transition into the podcast's own detail view and silently
    // fail to fire (the alert then belongs to a sidebar view that's mid-teardown).
    @State private var pendingUnsubscribeIDs = Set<UUID>()
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

    /// Downloaded+unplayed episode counts keyed by podcast ID. Must be called ONCE per body
    /// evaluation and the result reused (see `body` below) - this was briefly a computed `var`
    /// referenced directly inside the podcast ForEach, which meant it silently rebuilt the
    /// entire dictionary from scratch for every single row (38 podcasts = 38 full rebuilds per
    /// render, growing worse as more got downloaded/played). That's what caused both the click
    /// lag and the refresh slowdown - a refresh triggers many @Query updates, and each one
    /// re-paid that same O(podcasts x records) cost.
    ///
    /// Played-state used to come from a `@Query` over every `isPlayed == true` PlaybackRecord -
    /// harmless when Episode rows (and their play state) got pruned by retention, but under the
    /// CloudKit-split architecture PlaybackRecord rows are never deleted, so that query grew to
    /// ~13,000 rows and rebuilding a Set from all of them (map + hash every episodeKey) on every
    /// single render - i.e. every click, since any @State change re-evaluates body - was costing
    /// most of a second by itself. downloadedEpisodesQuery is tiny (usually single digits to
    /// tens), so scope the PlaybackRecord lookup to just those keys via
    /// PlaybackRecordStore.states(forKeys:in:), which becomes a cheap SQL IN-clause instead of
    /// pulling and hashing the entire played-history table in Swift.
    private func computeDownloadedUnplayedCounts() -> [UUID: Int] {
        guard !downloadedEpisodesQuery.isEmpty else { return [:] }
        let downloadedKeys = Set(downloadedEpisodesQuery.map(\.episodeKey))
        let states = PlaybackRecordStore.states(forKeys: downloadedKeys, in: modelContext)
        var counts: [UUID: Int] = [:]
        for episode in downloadedEpisodesQuery where !(states[episode.episodeKey]?.isPlayed ?? false) {
            counts[episode.podcastID, default: 0] += 1
        }
        return counts
    }

    var body: some View {
        let queueCount = queuedRecords.count
        let downloadedUnplayedCounts = computeDownloadedUnplayedCounts()

        List(selection: $multiSelection) {
            // Queue section at top
            Section {
                QueueRowView(queueCount: queueCount, iconSize: settings.sidebarIconSizeEnum.points, fontSize: settings.sidebarIconSizeEnum.fontSize)
                    .tag(Self.queueTag)
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingUnsubscribeIDs = [podcast.id]
                                    showingUnsubscribeAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                
                                Button {
                                    markAllAsPlayed(for: [podcast])
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
                                    // Same selection-aware pattern as Unsubscribe below: act on
                                    // the whole multi-selection only if the right-clicked row is
                                    // actually part of it, otherwise just the clicked row.
                                    if selectedPodcastIDs.count > 1 && selectedPodcastIDs.contains(podcast.id) {
                                        markAllAsPlayed(for: podcasts.filter { selectedPodcastIDs.contains($0.id) })
                                    } else {
                                        markAllAsPlayed(for: [podcast])
                                    }
                                }

                                Button("Unsubscribe", role: .destructive) {
                                    if selectedPodcastIDs.count > 1 && selectedPodcastIDs.contains(podcast.id) {
                                        // Act on the existing multi-selection
                                        pendingUnsubscribeIDs = selectedPodcastIDs
                                    } else {
                                        // Single item context menu - target just this row,
                                        // without disturbing multiSelection/navigation.
                                        pendingUnsubscribeIDs = [podcast.id]
                                    }
                                    showingUnsubscribeAlert = true
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
                pendingUnsubscribeIDs = selectedPodcastIDs
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
                        podcastSearchCoordinator.showDialog()
                    } label: {
                        Label("Search Podcasts…", systemImage: "magnifyingglass")
                    }

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
        .alert(pendingUnsubscribeIDs.count == 1 ? "Unsubscribe from Podcast?" : "Unsubscribe from \(pendingUnsubscribeIDs.count) Podcasts?",
               isPresented: $showingUnsubscribeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unsubscribe", role: .destructive) {
                unsubscribeSelected()
            }
        } message: {
            if pendingUnsubscribeIDs.count == 1,
               let selectedID = pendingUnsubscribeIDs.first,
               let podcast = podcasts.first(where: { $0.id == selectedID }) {
                Text("Are you sure you want to unsubscribe from \"\(podcast.title)\"? This will delete all downloaded episodes.")
            } else {
                Text("Are you sure you want to unsubscribe from \(pendingUnsubscribeIDs.count) podcasts? This will delete all downloaded episodes.")
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings, autoRefreshManager: autoRefreshManager)
        }
        #endif
    }
    
    private func unsubscribeSelected() {
        let podcastsToDelete = podcasts.filter { pendingUnsubscribeIDs.contains($0.id) }

        // Check if we're deleting a podcast that has the currently playing episode
        if let currentEpisode = audioPlayer.currentEpisode {
            let currentPodcastID = currentEpisode.podcastID
            let isDeletingCurrentPodcast = podcastsToDelete.contains { $0.id == currentPodcastID }

            if isDeletingCurrentPodcast {
                audioPlayer.stop()
            }
        }

        let subscriptionManager = SubscriptionManager(modelContext: modelContext)
        subscriptionManager.unsubscribe(podcasts: podcastsToDelete)

        // Only clear selection/navigation for podcasts that were actually part of it - a
        // swipe or single-item context menu action never touched multiSelection/selectedPodcast
        // in the first place, so there's nothing to unwind there.
        multiSelection.subtract(pendingUnsubscribeIDs)
        if let selectedPodcast, pendingUnsubscribeIDs.contains(selectedPodcast.id) {
            self.selectedPodcast = nil
        }
        pendingUnsubscribeIDs.removeAll()
    }

    // Only downloaded, not-yet-played episodes - "Mark All as Played" means "I'm done with what
    // I downloaded from this podcast," not "erase this podcast's entire back-catalog history."
    // That filter also keeps the batch naturally small (bounded by what's actually downloaded,
    // not by however many thousand episodes the feed has ever listed), so a single fetch+save
    // is enough - no chunking needed. Earlier versions of this tried chunking a much bigger,
    // unfiltered batch to avoid freezing the UI, which multiplied save() calls (one CloudKit
    // export-scheduling request each) far past what even the original per-podcast-loop bug did.
    private func markAllAsPlayed(for podcastsToMark: [Podcast]) {
        let podcastIDs = Set(podcastsToMark.map(\.id))
        guard !podcastIDs.isEmpty else { return }

        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { $0.isDownloaded && podcastIDs.contains($0.podcastID) }
        )
        guard let downloadedEpisodes = try? modelContext.fetch(descriptor) else { return }

        let downloadedKeys = Set(downloadedEpisodes.map(\.episodeKey))
        let states = PlaybackRecordStore.states(forKeys: downloadedKeys, in: modelContext)
        let episodesToMark = downloadedEpisodes.filter { !(states[$0.episodeKey]?.isPlayed ?? false) }
        guard !episodesToMark.isEmpty else { return }

        for episode in episodesToMark {
            PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).isPlayed = true
        }
        try? modelContext.save()
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

struct EpisodeRowView: View {
    let item: EpisodeDisplay
    let onShowInfo: (Episode) -> Void
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @Environment(\.modelContext) private var modelContext

    private var episode: Episode { item.episode }

    // Cache stripped description to avoid repeated HTML processing
    private let strippedDescription: String?

    init(item: EpisodeDisplay, onShowInfo: @escaping (Episode) -> Void) {
        self.item = item
        self.onShowInfo = onShowInfo
        self.strippedDescription = item.episode.episodeDescription?.stripHTMLTags()
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
                    if item.state.playbackPosition > 0 && !item.state.isPlayed {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        if let duration = episode.duration, duration > 0 {
                            let percent = Int((item.state.playbackPosition / duration) * 100)
                            Text("\(percent)% played")
                                .font(.appCaption)
                                .foregroundStyle(.blue)
                        }
                    }

                    Spacer()

                    if item.state.isPlayed {
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

            if item.state.isPlayed {
                Button {
                    PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).isPlayed = false
                    try? modelContext.save()
                } label: {
                    Label("Mark as Unplayed", systemImage: "circle")
                }
            } else {
                Button {
                    PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).isPlayed = true
                    try? modelContext.save()
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
    @EnvironmentObject var playbackProgress: PlaybackProgress
    @State var hoveringOverArt = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // Episode artwork thumbnail
                if let episode = audioPlayer.currentEpisode,
                   let podcast = audioPlayer.currentPodcast,
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
                    #if os(macOS)
                    .shadow(color: .black.opacity(hoveringOverArt ? 0.4 : 0), radius: 3, x: 0, y: 0)
                    .brightness(hoveringOverArt ? 0.05 : 0)
                    .help(Text("Click to open Mini Player"))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveringOverArt = hovering
                            if (hovering) {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .onTapGesture {
                        MenuCoordinator.shared.audioPlayer?.showMiniPlayer()
                    }
                    #endif
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

                        if let podcast = audioPlayer.currentPodcast {
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
                                    width: geometry.size.width * CGFloat(progressFraction),
                                    height: 4
                                )
                        }
                        .onTapGesture { location in
                            let progress = location.x / geometry.size.width
                            audioPlayer.seek(to: playbackProgress.duration * Double(progress))
                        }
                    }
                    .frame(height: 4)
                    
                    // Time labels
                    HStack {
                        Text(formatTime(playbackProgress.currentTime))
                            .font(.appCaption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(formatTime(playbackProgress.duration))
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
                                if abs(playbackProgress.playbackRate - Float(speed)) < 0.01 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge")
                        Text("\(playbackProgress.playbackRate, specifier: "%.2f")x")
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
    private var progressFraction: Double {
        guard playbackProgress.duration > 0 else { return 0 }
        return min(playbackProgress.currentTime / playbackProgress.duration, 1)
    }
}
#endif

// MARK: - Episode Detail View

struct EpisodeDetailView: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var podcastDirectory: PodcastDirectory

    // Played/position/queue state lives on PlaybackRecord, not Episode (see Models.swift) -
    // queried live here (rather than passed in as EpisodeDisplay) so this sheet stays reactive
    // to changes arriving from other devices while it's open.
    @Query private var matchingRecords: [PlaybackRecord]

    init(episode: Episode) {
        self.episode = episode
        let key = episode.episodeKey
        _matchingRecords = Query(filter: #Predicate<PlaybackRecord> { $0.episodeKey == key })
    }

    private var state: EpisodeState {
        matchingRecords.first.map { EpisodeState(record: $0) } ?? EpisodeState()
    }

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
                    if let artworkURL = episode.artworkURL ?? podcastDirectory.podcast(for: episode.podcastID)?.artworkURL,
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
                        if let podcast = podcastDirectory.podcast(for: episode.podcastID) {
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

                                if state.isPlayed {
                                    Label("Played", systemImage: "checkmark.circle.fill")
                                        .font(.appFootnote)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }

                                if state.queuePosition != nil {
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
                            if state.playbackPosition > 0 && !state.isPlayed {
                                if let duration = episode.duration, duration > 0 {
                                    VStack(spacing: 4) {
                                        HStack {
                                            Text("Progress")
                                                .font(.appFootnote)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(Int((state.playbackPosition / duration) * 100))%")
                                                .font(.appFootnote)
                                                .foregroundStyle(.secondary)
                                        }

                                        // A GeometryReader-based bar relied on List handing
                                        // each row a well-defined width top-down; outside a
                                        // List that proposal can go ambiguous, and the NaN
                                        // width it produced blanked out this entire sheet.
                                        // ProgressView doesn't have that failure mode.
                                        ProgressView(value: state.playbackPosition, total: duration)
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
                        if state.isPlayed {
                            Button {
                                PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).isPlayed = false
                                try? modelContext.save()
                            } label: {
                                Label("Mark as Unplayed", systemImage: "circle")
                            }
                        } else {
                            Button {
                                PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).isPlayed = true
                                try? modelContext.save()
                            } label: {
                                Label("Mark as Played", systemImage: "checkmark.circle")
                            }
                        }

                        // Add to / Remove from queue
                        if state.queuePosition != nil {
                            Button {
                                PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).queuePosition = nil
                                try? modelContext.save()
                            } label: {
                                Label("Remove from Queue", systemImage: "minus.circle")
                            }
                        } else {
                            Button {
                                // Add to end of queue. Scoped to queuePosition != nil (the
                                // queue itself, always small) rather than fetching every
                                // PlaybackRecord ever created (~13,000+ rows and growing).
                                let descriptor = FetchDescriptor<PlaybackRecord>(
                                    predicate: #Predicate { $0.queuePosition != nil }
                                )
                                let maxPosition = (try? modelContext.fetch(descriptor))?.compactMap { $0.queuePosition }.max() ?? -1
                                let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext)
                                record.queuePosition = maxPosition + 1
                                try? modelContext.save()
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
