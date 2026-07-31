//
//  ContentView.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI
import Combine
import SwiftData

struct ContentView: View {
    @EnvironmentObject var opmlCoordinator: OPMLImportCoordinator
    @EnvironmentObject var refreshCoordinator: RefreshCoordinator
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @State private var showingImportProgress = false
    @State private var importCompletedMessage: String?
    @State private var selectedPodcast: Podcast?
    @State private var showingQueue = false

    var body: some View {
#if os(macOS)
        VStack(spacing: 0) {
            NavigationSplitView {
                PodcastListView(selectedPodcast: $selectedPodcast, showingQueue: $showingQueue)
            } detail: {
                if showingQueue {
                    QueueView()
                        .id("queue") // Force refresh when switching to queue
                } else if let podcast = selectedPodcast {
                    PodcastDetailView(podcast: podcast)
                        .id(podcast.id) // Force new view when podcast changes
                } else {
                    NowPlayingView()
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
            } else if let message = refreshCoordinator.refreshCompleted {
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
        .onChange(of: opmlCoordinator.isImporting) { showingImportProgress = $0 }
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
        NavigationSplitView {
            PodcastListView(selectedPodcast: $selectedPodcast, showingQueue: $showingQueue)
        } detail: {
            if showingQueue {
                QueueView()
                    .id("queue") // Force refresh when switching to queue
            } else if let podcast = selectedPodcast {
                PodcastDetailView(podcast: podcast)
                    .id(podcast.id) // Force new view when podcast changes
            } else {
                NowPlayingView()
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
            } else if let message = refreshCoordinator.refreshCompleted {
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
        .onChange(of: opmlCoordinator.isImporting) { showingImportProgress = $0 }
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
    @Query(filter: #Predicate<Episode> { episode in
        episode.queuePosition != nil && !episode.isPlayed
    }) private var queuedEpisodes: [Episode]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var refreshCoordinator: RefreshCoordinator
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var settings: AppSettings
    @Binding var selectedPodcast: Podcast?
    @Binding var showingQueue: Bool
    @State private var showingSettings = false
    @State private var autoRefreshManager: AutoRefreshManager?
    @State private var multiSelection = Set<UUID>()
    @State private var showingUnsubscribeAlert = false
    @FocusState private var isFocused: Bool
    
    private var queueCount: Int {
        queuedEpisodes.count
    }
    
    var body: some View {
        List(selection: $multiSelection) {
            // Queue section at top
            Section {
                QueueRowView(queueCount: queueCount, isSelected: showingQueue, iconSize: settings.sidebarIconSizeEnum.points, fontSize: settings.sidebarIconSizeEnum.fontSize)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingQueue = true
                        selectedPodcast = nil
                        multiSelection.removeAll()
                    }
            }
            
            // Podcasts section
            Section("Podcasts") {
                if podcasts.isEmpty {
                    Text("No podcasts yet. Import an OPML file to get started!")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(podcasts) { podcast in
                        PodcastRowView(podcast: podcast, iconSize: settings.sidebarIconSizeEnum.points, fontSize: settings.sidebarIconSizeEnum.fontSize)
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
                                .disabled(multiSelection.count > 1)
                                
                                Button("Mark All as Played") {
                                    markAllAsPlayed(for: podcast)
                                }
                                
                                Button("Unsubscribe", role: .destructive) {
                                    if multiSelection.count > 1 && multiSelection.contains(podcast.id) {
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
        .onChange(of: multiSelection) { newSelection in
            // Update selectedPodcast when single selection changes
            if newSelection.count == 1, 
               let selectedID = newSelection.first,
               let podcast = podcasts.first(where: { $0.id == selectedID }) {
                showingQueue = false
                selectedPodcast = podcast
            } else if newSelection.isEmpty {
                selectedPodcast = nil
            }
        }
        .onDeleteCommand {
            if !multiSelection.isEmpty {
                showingUnsubscribeAlert = true
            }
        }
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
                Button(action: {
                    showingSettings = true
                }) {
                    Label("Settings", systemImage: "gear")
                }
            }
            #endif
        }
        .alert(multiSelection.count == 1 ? "Unsubscribe from Podcast?" : "Unsubscribe from \(multiSelection.count) Podcasts?", 
               isPresented: $showingUnsubscribeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unsubscribe", role: .destructive) {
                unsubscribeSelected()
            }
        } message: {
            if multiSelection.count == 1, 
               let selectedID = multiSelection.first,
               let podcast = podcasts.first(where: { $0.id == selectedID }) {
                Text("Are you sure you want to unsubscribe from \"\(podcast.title)\"? This will delete all downloaded episodes.")
            } else {
                Text("Are you sure you want to unsubscribe from \(multiSelection.count) podcasts? This will delete all downloaded episodes.")
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings, autoRefreshManager: autoRefreshManager)
        }
        #endif
    }
    
    private func unsubscribeSelected() {
        let podcastsToDelete = podcasts.filter { multiSelection.contains($0.id) }
        
        // Check if we're deleting a podcast that has the currently playing episode
        if let currentEpisode = audioPlayer.currentEpisode {
            let isDeletingCurrentPodcast = podcastsToDelete.contains { podcast in
                podcast.episodes.contains { $0.id == currentEpisode.id }
            }
            
            if isDeletingCurrentPodcast {
                audioPlayer.stop()
            }
        }
        
        for podcast in podcastsToDelete {
            modelContext.delete(podcast)
        }
        
        try? modelContext.save()
        multiSelection.removeAll()
        selectedPodcast = nil
    }
    
    private func markAllAsPlayed(for podcast: Podcast) {
        for episode in podcast.episodes {
            episode.isPlayed = true
        }
        try? modelContext.save()
    }
}

struct QueueRowView: View {
    let queueCount: Int
    let isSelected: Bool
    let iconSize: CGFloat
    let fontSize: CGFloat
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon matching the podcast artwork size
            ZStack {
                LinearGradient(
                    colors: [.orange, .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: iconSize * 0.4))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: iconSize, height: iconSize)
            .cornerRadius(6)
            
            Text("Queue")
                .font(.system(size: fontSize))
            
            Spacer()
            
            // Queue count badge
            if queueCount > 0 {
                Text("\(queueCount)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

struct PodcastRowView: View {
    let podcast: Podcast
    let iconSize: CGFloat
    let fontSize: CGFloat
    
    // Cache computed values to avoid recalculating on every render
    private let downloadedUnplayedCount: Int
    
    init(podcast: Podcast, iconSize: CGFloat, fontSize: CGFloat) {
        self.podcast = podcast
        self.iconSize = iconSize
        self.fontSize = fontSize
        self.downloadedUnplayedCount = podcast.episodes.filter { $0.isDownloaded && !$0.isPlayed }.count
    }
    
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
                .font(.system(size: fontSize))
            
            Spacer()
            
            // Downloaded & unplayed badge
            if downloadedUnplayedCount > 0 {
                Text("\(downloadedUnplayedCount)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
        }
        .padding(.vertical, 4)
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
                        EpisodeRowView(episode: episode)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(podcast.title)
    }
}

struct EpisodeRowView: View {
    let episode: Episode
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @State private var showingDetail = false
    
    // Cache stripped description to avoid repeated HTML processing
    private let strippedDescription: String?
    
    init(episode: Episode) {
        self.episode = episode
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                HStack {
                    Text(episode.publishDate, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    if let duration = episode.duration {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    // Show progress if partially played
                    if episode.playbackPosition > 0 && !episode.isPlayed {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        if let duration = episode.duration, duration > 0 {
                            let percent = Int((episode.playbackPosition / duration) * 100)
                            Text("\(percent)% played")
                                .font(.caption2)
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
                showingDetail = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Show episode details")
        }
        .contextMenu {
            Button {
                showingDetail = true
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
        .sheet(isPresented: $showingDetail) {
            EpisodeDetailView(episode: episode)
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
                                .font(.caption)
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
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        if let podcast = episode.podcast {
                            Text(podcast.title)
                                .font(.caption)
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
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Skip backward 15 seconds")
                    
                    // Play/Pause
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                    .help(audioPlayer.isPlaying ? "Pause" : "Play")
                    
                    // Skip forward
                    Button {
                        audioPlayer.skipForward()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.title3)
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
                                    width: geometry.size.width * CGFloat(audioPlayer.currentTime / max(audioPlayer.duration, 1)),
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
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(formatTime(audioPlayer.duration))
                            .font(.caption2)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 70)
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
}

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
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                
                                // Duration
                                if let duration = episode.duration {
                                    Label {
                                        Text(formatDuration(duration))
                                    } icon: {
                                        Image(systemName: "clock")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            
                            // Status badges
                            HStack(spacing: 12) {
                                if episode.isDownloaded {
                                    Label("Downloaded", systemImage: "arrow.down.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.green)
                                        .cornerRadius(12)
                                }
                                
                                if episode.isPlayed {
                                    Label("Played", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }
                                
                                if episode.queuePosition != nil {
                                    Label("In Queue", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        .font(.caption)
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
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(Int((episode.playbackPosition / duration) * 100))%")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        GeometryReader { geometry in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.gray.opacity(0.2))
                                                
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.accentColor)
                                                    .frame(width: geometry.size.width * CGFloat(episode.playbackPosition / duration))
                                            }
                                        }
                                        .frame(height: 8)
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
                                    .font(.caption)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
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
                
                ToolbarItem(placement: .primaryAction) {
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
    
    var body: some View {
        if let attributedString = htmlToAttributedString(html) {
            Text(AttributedString(attributedString))
                .font(.body)
                .foregroundStyle(.secondary)
        } else {
            // Fallback to plain text with HTML stripped
            Text(html.stripHTMLTags())
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
    
    private func htmlToAttributedString(_ html: String) -> NSAttributedString? {
        // Wrap in a basic HTML document with styling
        let styledHTML =
"""
<html>
<head>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            font-size: 16px;
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
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodingHTMLEntities()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    ContentView()
}
