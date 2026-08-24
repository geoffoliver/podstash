//
//  QueueView.swift
//  Podstash
//

import SwiftUI
import SwiftData

struct QueueView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var podcastDirectory: PodcastDirectory
    // Query directly for queued PlaybackRecords instead of filtering all episodes - queue/
    // played state lives on PlaybackRecord now, not Episode (see Models.swift). Joined to local
    // Episode metadata by episodeKey in `queuedEpisodes` below.
    @Query(
        filter: #Predicate<PlaybackRecord> { record in
            record.queuePosition != nil && !record.isPlayed
        },
        sort: \PlaybackRecord.queuePosition
    ) private var queuedRecords: [PlaybackRecord]

    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @State private var multiSelection = Set<UUID>()
    @State private var showingRemoveAlert = false
    @State private var episodeForInfoSheet: Episode?
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    #if !os(macOS)
    @State private var editMode: EditMode = .inactive
    #endif

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Joins queuedRecords (the reactive, CloudKit-synced source of truth for order/played) to
    // their local Episode metadata, scoped to just the keys in the queue - never a full-library
    // fetch. Records whose Episode hasn't been locally re-derived from RSS yet (e.g. this device
    // hasn't refreshed that podcast) are simply skipped until it has.
    private var queuedEpisodes: [EpisodeDisplay] {
        guard !queuedRecords.isEmpty else { return [] }
        let keys = Set(queuedRecords.map(\.episodeKey))
        let episodeDescriptor = FetchDescriptor<Episode>(predicate: #Predicate { keys.contains($0.episodeKey) })
        let episodes = (try? modelContext.fetch(episodeDescriptor)) ?? []
        let episodeByKey = PlaybackRecordStore.firstByKey(episodes)

        return queuedRecords.compactMap { record in
            guard let episode = episodeByKey[record.episodeKey] else { return nil }
            return EpisodeDisplay(episode: episode, state: EpisodeState(record: record))
        }
    }

    private func displayedEpisodes(from queuedEpisodes: [EpisodeDisplay]) -> [EpisodeDisplay] {
        guard isSearching else { return queuedEpisodes }
        return queuedEpisodes.filter { item in
            item.episode.title.localizedCaseInsensitiveContains(searchText)
                || (podcastDirectory.podcast(for: item.episode.podcastID)?.title.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        // Computed ONCE per body evaluation and reused below - queuedEpisodes does a real
        // SwiftData fetch, and was previously a bare computed property referenced ~4 times per
        // render (directly, and again indirectly through the old displayedEpisodes property),
        // same mistake as PodcastListView/PodcastDetailView's version of this bug.
        let queuedEpisodesList = queuedEpisodes
        let displayedEpisodesList = displayedEpisodes(from: queuedEpisodesList)

        Group {
            #if os(macOS)
            // macOS: Use proper NSTableView for double-click support
            VStack(spacing: 0) {
                if queuedEpisodesList.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("Queue is Empty")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Add episodes to your queue from any podcast")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isSearching && displayedEpisodesList.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Results")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("No queued episodes match \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    QueueTableView(
                        episodes: displayedEpisodesList,
                        podcastDirectory: podcastDirectory,
                        podcastDirectoryRevision: podcastDirectory.revision,
                        selection: $multiSelection,
                        onDoubleClick: { episode in
                            audioPlayer.play(episode: episode)
                        },
                        onRemove: { episodes in
                            // Simply remove from queue - no reindexing needed
                            for episode in episodes {
                                PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).queuePosition = nil
                            }

                            // Single save
                            try? modelContext.save()
                            multiSelection.removeAll()
                        },
                        onMarkPlayed: { episodes in
                            // Mark episodes as played immediately in memory
                            for episode in episodes {
                                let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext)
                                record.isPlayed = true
                                record.queuePosition = nil
                                record.playbackPosition = 0
                            }

                            // Clear selection immediately for instant UI feedback
                            multiSelection.removeAll()

                            // Save synchronously - required for SwiftData
                            try? modelContext.save()

                            // If current episode was marked, play next
                            if let currentID = audioPlayer.currentEpisode?.id,
                               episodes.contains(where: { $0.id == currentID }) {
                                playNextInQueue()
                            }
                        },
                        onMove: { indices, destination in
                            // Reordering during a filtered search would map indices
                            // onto the wrong episodes, so ignore it while searching.
                            guard !isSearching else { return }
                            moveEpisodes(from: indices, to: destination)
                        },
                        onShowInfo: { episode in
                            episodeForInfoSheet = episode
                        },
                        currentlyPlayingID: audioPlayer.currentEpisode?.id,
                        isPlaying: audioPlayer.isPlaying
                    )
                }
            }
            .navigationTitle("Queue")
            .searchable(text: $searchText, prompt: "Search Queue")
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            .onKeyPress(.return) {
                if let selectedID = multiSelection.first,
                   multiSelection.count == 1,
                   let item = queuedEpisodesList.first(where: { $0.episode.id == selectedID }) {
                    audioPlayer.play(episode: item.episode)
                    return .handled
                }
                return .ignored
            }
            .onDeleteCommand {
                if !multiSelection.isEmpty {
                    showingRemoveAlert = true
                }
            }
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button {
                            addAllUnplayedToQueue()
                        } label: {
                            Label("Add All Unplayed", systemImage: "plus.circle")
                        }

                        Button {
                            clearQueue()
                        } label: {
                            Label("Clear Queue", systemImage: "trash")
                        }
                        .disabled(queuedEpisodesList.isEmpty)
                    } label: {
                        Label("Queue Options", systemImage: "ellipsis.circle")
                    }
                }
            }
            #else
            // iOS: Use SwiftUI List
            List(selection: $multiSelection) {
            if queuedEpisodesList.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Queue is Empty")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Add episodes to your queue from any podcast")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if isSearching && displayedEpisodesList.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("No Results")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("No queued episodes match \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(displayedEpisodesList) { item in
                    QueueEpisodeRow(item: item, onShowInfo: { episodeForInfoSheet = $0 }, podcast: podcastDirectory.podcast(for: item.episode.podcastID))
                        .tag(item.episode.id)
                        .environmentObject(audioPlayer)
                        .simultaneousGesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    audioPlayer.play(episode: item.episode)
                                }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                removeFromQueue(item.episode)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                markAsPlayed(item.episode)
                            } label: {
                                Label("Mark Played", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                        .contextMenu {
                            Button {
                                audioPlayer.play(episode: item.episode)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .disabled(multiSelection.count > 1)

                            Divider()

                            Button {
                                if multiSelection.count > 1 {
                                    // Mark all selected as played
                                    markSelectedAsPlayed()
                                } else {
                                    markAsPlayed(item.episode)
                                }
                            } label: {
                                if multiSelection.count > 1 {
                                    Label("Mark \(multiSelection.count) as Played", systemImage: "checkmark.circle")
                                } else {
                                    Label("Mark as Played", systemImage: "checkmark.circle")
                                }
                            }

                            Button(role: .destructive) {
                                if multiSelection.count > 1 {
                                    // Remove all selected
                                    showingRemoveAlert = true
                                } else {
                                    removeFromQueue(item.episode)
                                }
                            } label: {
                                if multiSelection.count > 1 {
                                    Label("Remove \(multiSelection.count) from Queue", systemImage: "trash")
                                } else {
                                    Label("Remove from Queue", systemImage: "trash")
                                }
                            }
                        }
                }
                .onMove { indices, destination in
                    // Reordering during a filtered search would map indices onto
                    // the wrong episodes, so ignore it while searching.
                    guard !isSearching else { return }
                    moveEpisodes(from: indices, to: destination)
                }
            }
        }
        .reservePlayerBarSpace(audioPlayer)
        .navigationTitle("Queue")
        // .navigationBarDrawer placement (rather than automatic): iOS 26 otherwise docks the
        // search field to the bottom of the screen, where it collides with CompactPlayerBar's
        // safeAreaInset and ends up hidden behind it whenever an episode is playing/paused.
        // displayMode: .automatic (not .always) - .always forces the drawer to stay expanded,
        // which fights .searchToolbarBehavior(.minimize) below and stops it from collapsing.
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Queue")
        // .minimize: collapses to a small icon in the nav bar until tapped, instead of always
        // reserving a full row below the title that pushes/hides content underneath it.
        .searchToolbarBehavior(.minimize)
        // Matches PodcastDetailView's inline title, which doesn't exhibit the search
        // drawer's visibility getting tied to large-title scroll/collapse state.
        .navigationBarTitleDisplayMode(.inline)
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }

            ToolbarItem {
                Menu {
                    Button {
                        addAllUnplayedToQueue()
                    } label: {
                        Label("Add All Unplayed", systemImage: "plus.circle")
                    }

                    Button {
                        clearQueue()
                    } label: {
                        Label("Clear Queue", systemImage: "trash")
                    }
                    .disabled(queuedEpisodesList.isEmpty)
                } label: {
                    Label("Queue Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .environment(\.editMode, $editMode)
        #endif
        }
        // Shared alert - now applied to Group
        .alert(multiSelection.count == 1 ? "Remove Episode from Queue?" : "Remove \(multiSelection.count) Episodes from Queue?",
               isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeSelectedFromQueue()
            }
        } message: {
            if multiSelection.count == 1 {
                Text("Are you sure you want to remove this episode from the queue?")
            } else {
                Text("Are you sure you want to remove \(multiSelection.count) episodes from the queue?")
            }
        }
        .sheet(item: $episodeForInfoSheet) { episode in
            EpisodeDetailView(episode: episode)
        }
    }

    private func markSelectedAsPlayed() {
        let episodesToMark = queuedEpisodes.filter { multiSelection.contains($0.episode.id) }

        withAnimation {
            for item in episodesToMark {
                let record = PlaybackRecordStore.recordForMutation(episodeKey: item.episode.episodeKey, in: modelContext)
                record.isPlayed = true
                record.queuePosition = nil
                record.playbackPosition = 0
            }

            // Single save - no reindexing
            try? modelContext.save()
        }
        multiSelection.removeAll()

        // If current episode was marked, play next
        if let currentID = audioPlayer.currentEpisode?.id,
           episodesToMark.contains(where: { $0.episode.id == currentID }) {
            playNextInQueue()
        }
    }

    private func removeSelectedFromQueue() {
        let episodesToRemove = queuedEpisodes.filter { multiSelection.contains($0.episode.id) }

        for item in episodesToRemove {
            PlaybackRecordStore.recordForMutation(episodeKey: item.episode.episodeKey, in: modelContext).queuePosition = nil
        }

        // Single save - no reindexing
        try? modelContext.save()
        multiSelection.removeAll()
    }

    private func removeFromQueue(_ episode: Episode) {
        PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).queuePosition = nil
        // Single save - no reindexing
        try? modelContext.save()
    }

    private func markAsPlayed(_ episode: Episode) {
        withAnimation {
            let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext)
            record.isPlayed = true
            record.queuePosition = nil
            record.playbackPosition = 0

            // Single save - no reindexing
            try? modelContext.save()
        }

        // If this was the currently playing episode, play next
        if audioPlayer.currentEpisode?.id == episode.id {
            playNextInQueue()
        }
    }

    private func moveEpisodes(from source: IndexSet, to destination: Int) {
        var episodes = queuedEpisodes
        episodes.move(fromOffsets: source, toOffset: destination)

        // Reindex all episodes with their new positions
        for (index, item) in episodes.enumerated() {
            PlaybackRecordStore.recordForMutation(episodeKey: item.episode.episodeKey, in: modelContext).queuePosition = index
        }

        try? modelContext.save()
    }

    private func addAllUnplayedToQueue() {
        // Fetch downloaded episodes that aren't in queue, oldest first
        let queuedKeys = Set(queuedRecords.map(\.episodeKey))
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { episode in
                episode.isDownloaded && !queuedKeys.contains(episode.episodeKey)
            },
            sortBy: [SortDescriptor(\.publishDate)] // Oldest first
        )

        guard let candidateEpisodes = try? modelContext.fetch(descriptor) else { return }

        // Exclude already-played episodes (played state lives on PlaybackRecord, not Episode,
        // so this can't be expressed in the predicate above). Scoped to just the candidate
        // episodes' keys rather than fetching every played PlaybackRecord (~13,000+ rows and
        // growing, since PlaybackRecord history is never pruned).
        let candidateKeys = Set(candidateEpisodes.map(\.episodeKey))
        let states = PlaybackRecordStore.states(forKeys: candidateKeys, in: modelContext)
        let unplayedEpisodes = candidateEpisodes.filter { !(states[$0.episodeKey]?.isPlayed ?? false) }

        var nextPosition = (queuedRecords.compactMap(\.queuePosition).max() ?? -1) + 1

        for episode in unplayedEpisodes {
            PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext).queuePosition = nextPosition
            nextPosition += 1
        }

        try? modelContext.save()
    }

    private func clearQueue() {
        for record in queuedRecords {
            record.queuePosition = nil
        }
        try? modelContext.save()
    }

    private func playNextInQueue() {
        if let nextItem = queuedEpisodes.first {
            audioPlayer.play(episode: nextItem.episode)
        }
    }
}

struct QueueEpisodeRow: View {
    let item: EpisodeDisplay
    let onShowInfo: (Episode) -> Void
    // Passed explicitly rather than resolved via @EnvironmentObject<PodcastDirectory> - on
    // macOS this row is instantiated inside an NSHostingView built directly by
    // QueueTableView.Coordinator (see QueueTableView.swift), which is an isolated SwiftUI root
    // that doesn't inherit the ambient environment from the rest of the view hierarchy. Same
    // reason isCurrentlyPlaying/isPlaying below are passed explicitly on macOS instead of read
    // from an environment object.
    let podcast: Podcast?

    private var episode: Episode { item.episode }

    #if os(macOS)
    // On macOS: Pass these explicitly to avoid environment object issues
    let isCurrentlyPlaying: Bool
    let isPlaying: Bool
    #else
    // On iOS: Use environment object as normal
    @EnvironmentObject var audioPlayer: AudioPlayerManager

    var isCurrentlyPlaying: Bool {
        audioPlayer.currentEpisode?.id == episode.id
    }

    var isPlaying: Bool {
        audioPlayer.isPlaying
    }
    #endif

    var body: some View {
        #if os(macOS)
        // On macOS: Row should be completely non-interactive
        // Selection and double-click are handled by NSTableView
        rowContent
        #else
        // On iOS: Button for tap to play
        Button {
            audioPlayer.play(episode: episode)
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        #endif
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            // Episode artwork or podcast artwork
            EpisodeThumbnail(artworkURLString: podcast?.artworkURL, videoURL: episode.videoURL) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)

            // Episode info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(episode.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isCurrentlyPlaying && isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.footnote)
                            .foregroundStyle(.blue)
                    }
                }

                if let podcast {
                    Text(podcast.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(episode.publishDate.formatted(date: .abbreviated, time: .omitted))

                    if let duration = episode.duration {
                        Text("•")
                        Text(formatDuration(duration))
                    }

                    // Show progress if partially played
                    if item.state.playbackPosition > 0 {
                        Text("•")
                        if let duration = episode.duration, duration > 0 {
                            let percent = Int((item.state.playbackPosition / duration) * 100)
                            Text("\(percent)%")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            }

            Spacer()

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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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

#Preview {
    QueueView()
        .environmentObject(AudioPlayerManager())
}
#if os(macOS)
import AppKit

struct TableRowDoubleClickHandler<Content: View>: NSViewRepresentable {
    @Binding var selection: Set<UUID>
    let onDoubleClick: (UUID) -> Void
    let content: () -> Content

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: content())

        // Find the NSTableView in the view hierarchy
        DispatchQueue.main.async {
            if let tableView = findTableView(in: hostingView) {
                tableView.doubleAction = #selector(context.coordinator.handleDoubleClick(_:))
                tableView.target = context.coordinator
                context.coordinator.tableView = tableView
            }
        }

        return hostingView
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, onDoubleClick: onDoubleClick)
    }

    private func findTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }

        for subview in view.subviews {
            if let tableView = findTableView(in: subview) {
                return tableView
            }
        }

        return nil
    }

    class Coordinator: NSObject {
        @Binding var selection: Set<UUID>
        let onDoubleClick: (UUID) -> Void
        weak var tableView: NSTableView?

        init(selection: Binding<Set<UUID>>, onDoubleClick: @escaping (UUID) -> Void) {
            self._selection = selection
            self.onDoubleClick = onDoubleClick
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView = tableView,
                  tableView.clickedRow >= 0 else { return }

            // Get the first selected item (or clicked item if no selection)
            if let selectedID = selection.first {
                onDoubleClick(selectedID)
            }
        }

        // This is what NSTableView actually calls
        @objc func onAction(_ sender: Any?) {
            handleDoubleClick(sender)
        }
    }
}
#endif
