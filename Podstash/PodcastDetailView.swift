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

    // Episode has no relationship to Podcast (see Models.swift) - queried directly by
    // podcastID instead of `podcast.episodes`.
    @Query private var episodesForPodcast: [Episode]

    enum EpisodeFilter {
        case unplayed, all
    }

    init(podcast: Podcast) {
        self.podcast = podcast
        let podcastID = podcast.id
        _episodesForPodcast = Query(filter: #Predicate<Episode> { $0.podcastID == podcastID })
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Eligibility (UnplayedEligibilityPolicy) needs played-state for every episode in this feed,
    // not just the downloaded ones - a non-downloaded episode can still qualify if it's newer
    // than the podcast's mostRecentlyPlayedDate. Still bounded to this one podcast's episodes
    // (episodesForPodcast), not the whole library. Used for the "Unplayed" tab's label, which is
    // shown regardless of which tab is actually selected.
    private func unplayedDownloadedCount() -> Int {
        guard !episodesForPodcast.isEmpty else { return 0 }
        let states = PlaybackRecordStore.states(forKeys: Set(episodesForPodcast.map(\.episodeKey)), in: modelContext)
        return episodesForPodcast.filter { episode in
            UnplayedEligibilityPolicy.isEligible(
                isDownloaded: episode.isDownloaded,
                isPlayed: states[episode.episodeKey]?.isPlayed ?? false,
                publishDate: episode.publishDate,
                mostRecentlyPlayedDate: podcast.mostRecentlyPlayedDate,
                newestKnownPublishDate: podcast.newestKnownPublishDate
            )
        }.count
    }

    // The episodes actually rendered for the current tab/search. Joins PlaybackRecord state
    // (and sorts) only over the smallest candidate set each mode actually needs - the podcast's
    // entire history is only ever touched for the "All" tab or an active search, never for the
    // default "Unplayed" case, which is the one that matters most for render cost since it's
    // the default and typically small regardless of how large the back-catalog has grown.
    private func displayedEpisodes() -> [EpisodeDisplay] {
        if isSearching {
            // Search scans title/description across every episode - that's a cheap Episode-only
            // text match, so PlaybackRecord state only gets joined for whatever actually matches,
            // not the full back-catalog.
            let matches = episodesForPodcast.filter { episode in
                episode.title.localizedCaseInsensitiveContains(searchText)
                    || (episode.episodeDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            return PlaybackRecordStore.display(for: matches, in: modelContext)
                .sorted(by: { $0.episode.publishDate > $1.episode.publishDate })
        }

        switch selectedTab {
        case .unplayed:
            return PlaybackRecordStore.display(for: episodesForPodcast, in: modelContext)
                .filter { item in
                    UnplayedEligibilityPolicy.isEligible(
                        isDownloaded: item.episode.isDownloaded,
                        isPlayed: item.state.isPlayed,
                        publishDate: item.episode.publishDate,
                        mostRecentlyPlayedDate: podcast.mostRecentlyPlayedDate,
                        newestKnownPublishDate: podcast.newestKnownPublishDate
                    )
                }
                .sorted(by: { $0.episode.publishDate > $1.episode.publishDate })
        case .all:
            // No way around joining state for everything here - "All" fundamentally means
            // every episode with its played/queue status, so this is the one path that pays
            // the full back-catalog cost, same as before this fix.
            return PlaybackRecordStore.display(for: episodesForPodcast, in: modelContext)
                .sorted(by: { $0.episode.publishDate > $1.episode.publishDate })
        }
    }

    var body: some View {
        content()
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
                Text("Are you sure you want to unsubscribe from \"\(podcast.title)\"? This will delete all downloaded episodes and playback history for this show.")
            }
            .sheet(item: $episodeForInfoSheet) { episode in
                EpisodeDetailView(episode: episode)
            }
    }

    @ViewBuilder
    private func content() -> some View {
        let filtered = displayedEpisodes()
        let unplayedCount = unplayedDownloadedCount()

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

            if episodesForPodcast.isEmpty {
                emptyEpisodesView
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            } else {
                // Tab picker - disabled while searching since search always looks
                // across all episodes regardless of which tab is selected.
                Picker("Filter", selection: $selectedTab) {
                    Text("Unplayed (\(unplayedCount))").tag(EpisodeFilter.unplayed)
                    Text("All (\(episodesForPodcast.count))").tag(EpisodeFilter.all)
                }
                .pickerStyle(.segmented)
                .padding()
                .disabled(isSearching)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                if isSearching && filtered.isEmpty {
                    noResultsView
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filtered) { item in
                        episodeRow(item)
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

            if episodesForPodcast.isEmpty {
                emptyEpisodesView
            } else {
                // Tab picker - disabled while searching since search always looks
                // across all episodes regardless of which tab is selected.
                Picker("Filter", selection: $selectedTab) {
                    Text("Unplayed (\(unplayedCount))").tag(EpisodeFilter.unplayed)
                    Text("All (\(episodesForPodcast.count))").tag(EpisodeFilter.all)
                }
                .pickerStyle(.segmented)
                .padding()
                .disabled(isSearching)

                if isSearching && filtered.isEmpty {
                    noResultsView
                } else {
                // Use List instead of ScrollView + ForEach for better performance (virtualization)
                List {
                    ForEach(filtered) { item in
                        episodeRow(item)
                    }
                }
                .listStyle(.plain)
                .reservePlayerBarSpace(audioPlayer)
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
    private func episodeRow(_ item: EpisodeDisplay) -> some View {
        let episode = item.episode
        HStack(spacing: 12) {
            Button {
                audioPlayer.play(episode: episode)
            } label: {
                EpisodeRowView(item: item, onShowInfo: { episodeForInfoSheet = $0 })
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
                Label(item.state.queuePosition != nil ? "Remove from Queue" : "Add to Queue",
                      systemImage: item.state.queuePosition != nil ? "text.badge.minus" : "text.badge.plus")
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

            if !item.state.isPlayed {
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
           episodesForPodcast.contains(where: { $0.id == currentEpisode.id }) {
            audioPlayer.stop()
        }

        let subscriptionManager = SubscriptionManager(modelContext: modelContext)
        subscriptionManager.unsubscribe(podcast: podcast)
        dismiss()
    }

    private func addToQueue(_ episode: Episode) {
        let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext)
        if record.queuePosition != nil {
            // Remove from queue
            record.queuePosition = nil
        } else {
            // Add to end of queue
            let descriptor = FetchDescriptor<PlaybackRecord>(
                predicate: #Predicate { rec in
                    rec.queuePosition != nil && !rec.isPlayed
                },
                sortBy: [SortDescriptor(\.queuePosition, order: .reverse)]
            )

            let maxPosition = (try? modelContext.fetch(descriptor))?.first?.queuePosition ?? -1
            record.queuePosition = maxPosition + 1
        }

        try? modelContext.save()
    }

    private func markAsPlayed(_ episode: Episode) {
        let record = PlaybackRecordStore.markPlayed(episode: episode, in: modelContext)
        record.queuePosition = nil
        record.playbackPosition = 0
        try? modelContext.save()
    }

    private func markAsUnplayed(_ episode: Episode) {
        PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).isPlayed = false
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
        EpisodeThumbnail(artworkURLString: podcast.artworkURL) {
            podcastPlaceholder
        }
        .frame(width: artworkSize, height: artworkSize)
        .cornerRadius(12)
        .shadow(radius: 3)
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
