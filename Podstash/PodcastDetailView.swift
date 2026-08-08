//
//  PodcastDetailView.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI
import SwiftData

struct PodcastDetailView: View {
    let podcast: Podcast
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var refreshCoordinator: RefreshCoordinator
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var showingUnsubscribeAlert = false
    @State private var selectedTab: EpisodeFilter = .unplayed
    @State private var episodeForInfoSheet: Episode?
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    enum EpisodeFilter {
        case unplayed, all
    }

    // Pre-sort episodes ONCE, not on every render
    private var sortedEpisodes: [Episode] {
        podcast.episodes.sorted(by: { $0.publishDate > $1.publishDate })
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredEpisodes: [Episode] {
        // Searching always looks across every episode, regardless of which tab is
        // selected - the tab picker is just a default view, not a search scope.
        let episodes = isSearching ? sortedEpisodes : {
            switch selectedTab {
            case .unplayed:
                // Only show unplayed episodes that are downloaded
                return sortedEpisodes.filter { !$0.isPlayed && $0.isDownloaded }
            case .all:
                return sortedEpisodes
            }
        }()

        guard isSearching else { return episodes }

        return episodes.filter { episode in
            episode.title.localizedCaseInsensitiveContains(searchText)
                || (episode.episodeDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private var unplayedDownloadedCount: Int {
        sortedEpisodes.filter { !$0.isPlayed && $0.isDownloaded }.count
    }
    
    var body: some View {
        content
            .navigationTitle(podcast.title)
            #if os(macOS)
            // Explicit .toolbar placement (rather than .automatic): this view has no
            // other toolbar items to anchor to, and without one .automatic falls back
            // to an inline drawer field that doesn't match the window's toolbar chrome.
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search Episodes")
            #else
            // displayMode: .automatic (not .always) - .always forces the drawer to stay
            // expanded, which fights .searchToolbarBehavior(.minimize) below and stops it
            // from collapsing.
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Episodes")
            // .minimize: collapses to a small icon in the nav bar until tapped, instead of
            // always reserving a full row below the title that pushes content down.
            .searchToolbarBehavior(.minimize)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("Unsubscribe from Podcast?", isPresented: $showingUnsubscribeAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Unsubscribe", role: .destructive) {
                    unsubscribe()
                }
            } message: {
                Text("Are you sure you want to unsubscribe from \"\(podcast.title)\"? This will delete all downloaded episodes.")
            }
            .sheet(item: $episodeForInfoSheet) { episode in
                EpisodeDetailView(episode: episode)
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        // Header and tab picker live inside the same List as the episodes (rather than a
        // fixed VStack above a separate List) so the nav bar can track this scroll view's
        // offset - that's what lets the search field collapse to an icon and reveal on
        // drag-down, matching QueueView, instead of always sitting visible below the title.
        List {
            PodcastHeaderView(
                podcast: podcast,
                onRefresh: { refreshCoordinator.refreshSingleFeed(podcast) },
                onUnsubscribe: { showingUnsubscribeAlert = true }
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            if podcast.episodes.isEmpty {
                emptyEpisodesView
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            } else {
                // Tab picker - disabled while searching since search always looks
                // across all episodes regardless of which tab is selected.
                Picker("Filter", selection: $selectedTab) {
                    Text("Unplayed (\(unplayedDownloadedCount))").tag(EpisodeFilter.unplayed)
                    Text("All (\(sortedEpisodes.count))").tag(EpisodeFilter.all)
                }
                .pickerStyle(.segmented)
                .padding()
                .disabled(isSearching)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                if isSearching && filteredEpisodes.isEmpty {
                    noResultsView
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredEpisodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
        }
        .listStyle(.plain)
        .reservePlayerBarSpace(audioPlayer)
        #else
        VStack(spacing: 0) {
            // Header with artwork and info
            PodcastHeaderView(
                podcast: podcast,
                onRefresh: {
                    refreshCoordinator.refreshSingleFeed(podcast)
                },
                onUnsubscribe: {
                    showingUnsubscribeAlert = true
                }
            )

            if podcast.episodes.isEmpty {
                emptyEpisodesView
            } else {
                // Tab picker - disabled while searching since search always looks
                // across all episodes regardless of which tab is selected.
                Picker("Filter", selection: $selectedTab) {
                    Text("Unplayed (\(unplayedDownloadedCount))").tag(EpisodeFilter.unplayed)
                    Text("All (\(sortedEpisodes.count))").tag(EpisodeFilter.all)
                }
                .pickerStyle(.segmented)
                .padding()
                .disabled(isSearching)

                if isSearching && filteredEpisodes.isEmpty {
                    noResultsView
                } else {
                // Use List instead of ScrollView + ForEach for better performance (virtualization)
                List {
                    ForEach(filteredEpisodes) { episode in
                        episodeRow(episode)
                    }
                }
                .listStyle(.plain)
                }
            }
        }
        #endif
    }

    private var emptyEpisodesView: some View {
        VStack(spacing: 16) {
            Text("No episodes yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Refresh this podcast to download episodes")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Button("Refresh Now") {
                refreshCoordinator.refreshSingleFeed(podcast)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Results")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("No episodes match \"\(searchText)\"")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func episodeRow(_ episode: Episode) -> some View {
        HStack(spacing: 12) {
            Button {
                audioPlayer.play(episode: episode)
            } label: {
                EpisodeRowView(episode: episode, onShowInfo: { episodeForInfoSheet = $0 })
            }
            .buttonStyle(.plain)

            // Download button at the end of the row
            if episode.isDownloaded {
                Button {
                    downloadManager.deleteDownload(episode)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.large)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Episode downloaded - tap to delete")
            } else if downloadManager.isDownloading(episode) {
                Button {
                    downloadManager.cancelDownload(episode)
                } label: {
                    ZStack {
                        CircularProgressView(progress: downloadManager.downloadProgress(for: episode) ?? 0.0)
                            .frame(width: 24, height: 24)

                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Downloading - tap to cancel")
            } else {
                Button {
                    downloadManager.downloadEpisode(episode)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                        .imageScale(.large)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Download episode")
            }
        }
        #if os(macOS)
        // .plain list style has no default row insets on macOS (unlike iOS), so without
        // this the episode text sits flush against the window edge.
        .padding(.horizontal)
        #endif
        .contextMenu {
            Button {
                audioPlayer.play(episode: episode)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                addToQueue(episode)
            } label: {
                Label(episode.queuePosition != nil ? "Remove from Queue" : "Add to Queue",
                      systemImage: episode.queuePosition != nil ? "text.badge.minus" : "text.badge.plus")
            }

            Divider()

            // Download context menu items
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
                    Label("Download Episode", systemImage: "arrow.down.circle")
                }
            }

            Divider()

            if !episode.isPlayed {
                Button {
                    markAsPlayed(episode)
                } label: {
                    Label("Mark as Played", systemImage: "checkmark.circle")
                }
            } else {
                Button {
                    markAsUnplayed(episode)
                } label: {
                    Label("Mark as Unplayed", systemImage: "circle")
                }
            }
        }
    }

    private func unsubscribe() {
        if let currentEpisode = audioPlayer.currentEpisode,
           podcast.episodes.contains(where: { $0.id == currentEpisode.id }) {
            audioPlayer.stop()
        }

        let subscriptionManager = SubscriptionManager(modelContext: modelContext)
        subscriptionManager.unsubscribe(podcast: podcast)
        dismiss()
    }
    
    private func addToQueue(_ episode: Episode) {
        if episode.queuePosition != nil {
            // Remove from queue
            episode.queuePosition = nil
        } else {
            // Add to end of queue
            let descriptor = FetchDescriptor<Episode>(
                predicate: #Predicate { ep in
                    ep.queuePosition != nil && !ep.isPlayed
                },
                sortBy: [SortDescriptor(\.queuePosition, order: .reverse)]
            )
            
            let maxPosition = (try? modelContext.fetch(descriptor))?.first?.queuePosition ?? -1
            episode.queuePosition = maxPosition + 1
        }
        
        try? modelContext.save()
    }
    
    private func markAsPlayed(_ episode: Episode) {
        episode.isPlayed = true
        episode.queuePosition = nil
        episode.playbackPosition = 0
        try? modelContext.save()
    }

    private func markAsUnplayed(_ episode: Episode) {
        episode.isPlayed = false
        try? modelContext.save()
    }
}

struct PodcastHeaderView: View {
    let podcast: Podcast
    let onRefresh: () -> Void
    let onUnsubscribe: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isDescriptionExpanded = false

    // Cache stripped description to avoid repeated HTML/regex processing on every render
    // (same pattern as EpisodeRowView.strippedDescription).
    private let strippedDescription: String?

    init(podcast: Podcast, onRefresh: @escaping () -> Void, onUnsubscribe: @escaping () -> Void) {
        self.podcast = podcast
        self.onRefresh = onRefresh
        self.onUnsubscribe = onUnsubscribe
        self.strippedDescription = podcast.podcastDescription?.stripHTMLTags()
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    // Rough character-count heuristic for "does this need a More/Less toggle",
    // rather than measuring rendered height. On macOS, feeding GeometryReader-measured
    // heights back into @State from inside a NavigationSplitView's detail pane caused
    // a layout feedback loop that made NSSplitViewController collapse the whole window
    // (sidebar + detail) when the description had significant content.
    private var isDescriptionTruncated: Bool {
        (strippedDescription?.count ?? 0) > 160
    }

    private var artworkSize: CGFloat {
        isCompact ? 96 : 160
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                artworkView

                // Info on right
                VStack(alignment: .leading, spacing: 8) {
                    // Title and Author
                    VStack(alignment: .leading, spacing: 2) {
                        Text(podcast.title)
                            .font(.title3)
                            .fontWeight(.bold)

                        if let author = podcast.author {
                            Text(author)
                                .font(.appBody)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Description
                    if let description = strippedDescription {
                        descriptionView(description)
                    }

                    // On regular width, the metadata row and buttons fit alongside the artwork.
                    if !isCompact {
                        metadataRow
                        actionButtons
                    }
                }

                if !isCompact {
                    Spacer()
                }
            }

            // On compact width, give the metadata row and buttons the full width so
            // they aren't squeezed into the narrow column next to the artwork.
            if isCompact {
                metadataRow
                actionButtons
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let lastUpdated = podcast.lastUpdated {
                Text(formattedLastUpdated(lastUpdated))
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
            }

            // Website link
            if let websiteURL = podcast.websiteURL, let url = URL(string: websiteURL) {
                Link(destination: url) {
                    Label("Web", systemImage: "safari")
                        .font(.appFootnote)
                }
            }
        }
    }

    private func descriptionView(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Expanded text is capped at a fixed height and scrolls internally rather than
            // using .fixedSize/lineLimit(nil) to grow to its full ideal height. Asking a
            // NavigationSplitView detail pane to accommodate an unbounded ideal height is
            // what made NSSplitViewController collapse the whole window on macOS.
            if isDescriptionExpanded {
                ScrollView {
                    Text(description)
                        .font(.appBody)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            } else {
                Text(description)
                    .font(.appBody)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDescriptionExpanded = true
                        }
                    }
            }

            if isDescriptionTruncated || isDescriptionExpanded {
                Text(isDescriptionExpanded ? "Less" : "More")
                    .font(.appFootnote.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isDescriptionExpanded.toggle()
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artworkURL = podcast.artworkURL, let url = URL(string: artworkURL) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                podcastPlaceholder
            }
            .frame(width: artworkSize, height: artworkSize)
            .cornerRadius(12)
            .shadow(radius: 3)
        } else {
            podcastPlaceholder
                .frame(width: artworkSize, height: artworkSize)
                .cornerRadius(12)
                .shadow(radius: 3)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.appBody)
                    .frame(maxWidth: isCompact ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button(action: onUnsubscribe) {
                Label("Unsubscribe", systemImage: "xmark.circle")
                    .font(.appBody)
                    .frame(maxWidth: isCompact ? .infinity : nil)
                    // The bordered button style's .tint(.red) below colors the text but leaves
                    // the SF Symbol rendered in the system accent color, so force it explicitly.
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.red)
        }
    }

    private func formattedLastUpdated(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        if Calendar.current.isDateInToday(date) {
            return "Updated \(timeFormatter.string(from: date))"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        return "Updated \(dateFormatter.string(from: date)) at \(timeFormatter.string(from: date))"
    }

    private var podcastPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "mic.fill")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
        }
    }
}

#Preview {
    NavigationStack {
        PodcastDetailView(podcast: Podcast(title: "Sample Podcast", feedURL: "https://example.com/feed"))
    }
    .environmentObject(RefreshCoordinator())
    .environmentObject(AudioPlayerManager())
    .environmentObject(DownloadManager())
}
