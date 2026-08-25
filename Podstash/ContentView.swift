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
    // Separate from refreshCoordinator so this view's frequent progress-tick re-renders (see
    // RefreshProgress.swift) don't propagate to other views that hold RefreshCoordinator itself.
    @EnvironmentObject var refreshProgress: RefreshProgress
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    // On compact width (iPhone), NavigationSplitView collapses sidebar/detail into a single-
    // column push/pop stack rather than showing them side by side - only the topmost column is
    // ever actually visible, so FloatingPlayerBar needs to be attached to both, or it vanishes
    // whenever the sidebar (Podcasts list) is the page on screen. On regular width (iPad
    // split, macOS) both columns render simultaneously, so it's scoped to the detail column only
    // - same reasoning as the macOS fix, so it doesn't span across the sidebar too.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                // FloatingPlayerBar overlays just the detail column here (not the whole window)
                // so it spans only the content area's width, not the sidebar too.
                Group {
                    if let podcast = selectedPodcast, !showingQueue {
                        PodcastDetailView(podcast: podcast)
                            .id(podcast.id) // Force new view when podcast changes
                    } else {
                        // Queue is the default/fallback detail view (also covers the case where
                        // a podcast gets deselected without Queue being clicked directly - see
                        // showingQueue's default-true comment above). NowPlayingView is no longer
                        // reachable here now that Queue is the default view; it's still used as
                        // the iOS sheet from FloatingPlayerBar.
                        QueueView()
                            .id("queue") // Force refresh when switching to queue
                    }
                }
                .overlay(alignment: .bottom) {
                    FloatingPlayerBar()
                        .environmentObject(audioPlayer)
                }
            }
            .frame(minWidth: 700, minHeight: 500)

            // Refresh status bar, docked full-width at the bottom - stays flush rather than
            // floating (unlike FloatingPlayerBar above, which is scoped to the detail column
            // only) since it's a transient system-style banner, not a persistent player. It
            // reserves its own layout row here, below the whole NavigationSplitView, so it can
            // never overlap the floating player bar.
            if refreshCoordinator.isRefreshing {
                RefreshStatusBar(
                    currentPodcastTitle: refreshProgress.currentPodcastTitle,
                    progress: refreshProgress.progress,
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
            // On regular width (iPad split), sidebar and detail render side by side, so the bar
            // is scoped here to avoid spanning across the sidebar too (matches the macOS fix).
            // On compact width (iPhone) it's the other overlay below instead - NOT this one -
            // because NavigationSplitView collapses to a push/pop stack there, and a column-level
            // overlay gets swept along with that column's own slide transition (tied to the page,
            // sliding in/out with it) instead of staying visually fixed like Apple's own mini
            // player. Attaching it outside the NavigationSplitView entirely, as a sibling rather
            // than a descendant of either column, is what keeps it put across navigation.
            Group {
                if let podcast = selectedPodcast, !showingQueue {
                    PodcastDetailView(podcast: podcast)
                        .id(podcast.id) // Force new view when podcast changes
                } else {
                    // Queue is the default/fallback detail view here too (see the macOS branch
                    // above for why). NowPlayingView is still used as the iPhone sheet from
                    // FloatingPlayerBar - that path is untouched.
                    QueueView()
                        .id("queue") // Force refresh when switching to queue
                }
            }
            .overlay(alignment: .bottom) {
                if horizontalSizeClass != .compact {
                    FloatingPlayerBar()
                        .environmentObject(audioPlayer)
                }
            }
        }
        // Refresh status bar, docked full-width at the bottom - stays flush rather than floating
        // (unlike FloatingPlayerBar) since it's a transient system-style banner, not a persistent
        // player. Its height is tracked so the floating player bar can position itself above it
        // instead of overlapping - NavigationSplitView's columns don't shrink in response to a
        // `.safeAreaInset` applied around the whole split view (see reservePlayerBarSpace's doc
        // comment for the same quirk), so this can't be left to layout the way it can on macOS.
        .safeAreaInset(edge: .bottom) {
            Group {
                if refreshCoordinator.isRefreshing {
                    RefreshStatusBar(
                        currentPodcastTitle: refreshProgress.currentPodcastTitle,
                        progress: refreshProgress.progress,
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
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                refreshCoordinator.statusBarHeight = height
            }
        }
        // Compact width (iPhone) only - a single instance attached here, as a sibling of the
        // NavigationSplitView rather than living inside either of its columns, so it stays fixed
        // on screen through the sidebar<->detail push/pop navigation instead of being tied to
        // whichever column currently owns it.
        .overlay(alignment: .bottom) {
            if horizontalSizeClass == .compact {
                FloatingPlayerBar()
                    .environmentObject(audioPlayer)
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
    // Cached result of computeDownloadedUnplayedCounts(), recomputed off the render path - see
    // that function's doc comment for why it must never be called directly from `body`.
    @State private var downloadedUnplayedCounts: [UUID: Int] = [:]
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

    /// Downloaded+unplayed episode counts keyed by podcast ID. MUST NEVER be called directly from
    /// `body` - only from the off-render-path recompute triggered by `.task` below (see
    /// `badgeRecomputeSignal`/`recomputeDownloadedUnplayedCounts`). It does a real
    /// `modelContext.fetch(...)` (and, via PlaybackRecordStore.states, another one), and calling
    /// that synchronously during body evaluation - on the same ModelContext `@Query` is also
    /// watching - was observed to send SwiftUI's Observation graph into a self-sustaining
    /// invalidate/re-render loop: body renders -> this fetches -> the fetch registers as a graph
    /// change -> body renders again, immediately, forever. Measured at ~70 calls/second, pegging
    /// the main thread at ~100% CPU until force-quit. This was previously a computed `var`
    /// referenced directly inside the podcast ForEach, which additionally rebuilt the entire
    /// dictionary from scratch for every single row (38 podcasts = 38 full rebuilds per render) -
    /// fixed by computing it once per render into a local, but that still left the once-per-render
    /// call sitting directly in body, which is what caused the render-loop above.
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
    // Beyond the downloaded set above, UnplayedEligibilityPolicy also admits a non-downloaded
    // episode newer than its podcast's mostRecentlyPlayedDate (or, with no play history yet, the
    // single newest known episode). That threshold differs per podcast, but rather than one
    // bounded fetch per podcast (which turned a refresh's frequent @Query-driven re-renders into
    // O(podcasts) SQL round trips per render - 38 subscriptions meant 38 synchronous fetches on
    // every progress tick, which is what made a refresh crawl and peg the CPU), this runs ONE
    // fetch bounded by the earliest threshold across all podcasts. Each candidate still gets
    // filtered against its own podcast's actual threshold below via isEligible, so the wider bound
    // doesn't change which episodes end up counted - it just replaces N round trips with one.
    private func computeDownloadedUnplayedCounts() -> [UUID: Int] {
        var candidateEpisodes = downloadedEpisodesQuery

        let perPodcastThresholds = podcasts.map { $0.mostRecentlyPlayedDate ?? $0.newestKnownPublishDate }
        if let threshold = UnplayedEligibilityPolicy.earliestEligibilityThreshold(perPodcastThresholds) {
            let descriptor = FetchDescriptor<Episode>(
                predicate: #Predicate<Episode> { $0.publishDate >= threshold }
            )
            if let recent = try? modelContext.fetch(descriptor) {
                candidateEpisodes.append(contentsOf: recent)
            }
        }

        guard !candidateEpisodes.isEmpty else { return [:] }

        // An episode can appear in both the downloaded query and a per-podcast recency fetch
        // above - dedupe by episodeKey before joining state, same helper QueueView.queuedEpisodes
        // uses for the same reason.
        let deduped = PlaybackRecordStore.firstByKey(candidateEpisodes).values
        let states = PlaybackRecordStore.states(forKeys: Set(deduped.map(\.episodeKey)), in: modelContext)
        let podcastsByID = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.id, $0) })

        var counts: [UUID: Int] = [:]
        for episode in deduped {
            let podcast = podcastsByID[episode.podcastID]
            let eligible = UnplayedEligibilityPolicy.isEligible(
                isDownloaded: episode.isDownloaded,
                isPlayed: states[episode.episodeKey]?.isPlayed ?? false,
                publishDate: episode.publishDate,
                mostRecentlyPlayedDate: podcast?.mostRecentlyPlayedDate,
                newestKnownPublishDate: podcast?.newestKnownPublishDate
            )
            if eligible {
                counts[episode.podcastID, default: 0] += 1
            }
        }
        return counts
    }

    /// Cheap, pure signal combining the @Query'd collections computeDownloadedUnplayedCounts
    /// depends on - safe to read directly in body (no SwiftData fetch, just counts/booleans
    /// already being tracked) so `.task(id:)` below can fire a recompute immediately when a
    /// refresh, download, or queue change makes the counts stale, without re-running the actual
    /// fetch on every render the way the old inline call did.
    private var badgeRecomputeSignal: Int {
        var hasher = Hasher()
        hasher.combine(podcasts.count)
        hasher.combine(downloadedEpisodesQuery.count)
        hasher.combine(queuedRecords.count)
        hasher.combine(refreshCoordinator.isRefreshing)
        return hasher.finalize()
    }

    private func recomputeDownloadedUnplayedCounts() {
        downloadedUnplayedCounts = computeDownloadedUnplayedCounts()
    }

    var body: some View {
        let queueCount = queuedRecords.count

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
        // Recomputes badge counts off the render path - see computeDownloadedUnplayedCounts's
        // doc comment for why this can never move into body directly. Fires immediately when
        // badgeRecomputeSignal changes (refresh progress, a download finishing, a queue change)...
        .task(id: badgeRecomputeSignal) {
            recomputeDownloadedUnplayedCounts()
        }
        // ...and this is the safety net for the cases that signal doesn't cover - e.g. marking a
        // downloaded-but-unqueued episode played from PodcastDetailView doesn't change any of
        // podcasts/downloadedEpisodesQuery/queuedRecords here, so nothing would otherwise tell
        // this view its badge counts just went stale. A low-frequency poll, not a per-render
        // fetch, so unlike the old inline call it can't feed back into a render loop.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                recomputeDownloadedUnplayedCounts()
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
            PlaybackRecordStore.markPlayed(episode: episode, in: modelContext)
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
            EpisodeThumbnail(artworkURLString: podcast.artworkURL) {
                podcastPlaceholder
            }
            .frame(width: iconSize, height: iconSize)
            .cornerRadius(6)
            
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
            // Without this the VStack only claims as much width as its text needs, so the
            // wrapping "play" Button in episodeRow (PodcastDetailView) - whose hit area is just
            // this label's own bounds - leaves the rest of the row dead to clicks/taps.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

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
                    PlaybackRecordStore.markPlayed(episode: episode, in: modelContext)
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
                    EpisodeThumbnail(
                        episode: episode,
                        podcast: podcastDirectory.podcast(for: episode.podcastID),
                        contentMode: .fit
                    ) {
                        artworkPlaceholder
                    }
                    // Fixed, not maxWidth/maxHeight - EpisodeThumbnail wraps its own
                    // GeometryReader, and inside this ScrollView's unbounded height proposal a
                    // GeometryReader given only a cap (rather than a concrete value) collapses
                    // toward zero instead of filling up to that cap.
                    .frame(width: 300, height: 300)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    
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
                        if let url = URL(string: episode.audioURL ?? "") {
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
                                PlaybackRecordStore.markPlayed(episode: episode, in: modelContext)
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
