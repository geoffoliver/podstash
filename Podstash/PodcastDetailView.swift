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
    @Environment(\.dismiss) private var dismiss
    
    enum EpisodeFilter {
        case unplayed, all
    }
    
    // Pre-sort episodes ONCE, not on every render
    private var sortedEpisodes: [Episode] {
        podcast.episodes.sorted(by: { $0.publishDate > $1.publishDate })
    }
    
    private var filteredEpisodes: [Episode] {
        switch selectedTab {
        case .unplayed:
            // Only show unplayed episodes that are downloaded
            return sortedEpisodes.filter { !$0.isPlayed && $0.isDownloaded }
        case .all:
            return sortedEpisodes
        }
    }
    
    private var unplayedDownloadedCount: Int {
        sortedEpisodes.filter { !$0.isPlayed && $0.isDownloaded }.count
    }
    
    var body: some View {
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
            } else {
                // Tab picker
                Picker("Filter", selection: $selectedTab) {
                    Text("Unplayed (\(unplayedDownloadedCount))").tag(EpisodeFilter.unplayed)
                    Text("All (\(sortedEpisodes.count))").tag(EpisodeFilter.all)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Use List instead of ScrollView + ForEach for better performance (virtualization)
                List {
                    ForEach(filteredEpisodes) { episode in
                        HStack(spacing: 12) {
                            Button {
                                audioPlayer.play(episode: episode)
                            } label: {
                                EpisodeRowView(episode: episode)
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
                                }
                                .buttonStyle(.plain)
                                .help("Episode downloaded - tap to delete")
                            } else if downloadManager.isDownloading(episode) {
                                ZStack {
                                    CircularProgressView(progress: downloadManager.downloadProgress(for: episode) ?? 0.0)
                                        .frame(width: 24, height: 24)
                                    
                                    Button {
                                        downloadManager.cancelDownload(episode)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .help("Downloading - tap to cancel")
                            } else {
                                Button {
                                    downloadManager.downloadEpisode(episode)
                                } label: {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(.blue)
                                        .imageScale(.large)
                                }
                                .buttonStyle(.plain)
                                .help("Download episode")
                            }
                        }
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
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(podcast.title)
        #if os(iOS)
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
    }
    
    private func unsubscribe() {
        modelContext.delete(podcast)
        try? modelContext.save()
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
}

struct PodcastHeaderView: View {
    let podcast: Podcast
    let onRefresh: () -> Void
    let onUnsubscribe: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Artwork on left
            if let artworkURL = podcast.artworkURL, let url = URL(string: artworkURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    podcastPlaceholder
                }
                .frame(width: 160, height: 160)
                .cornerRadius(12)
                .shadow(radius: 3)
            } else {
                podcastPlaceholder
                    .frame(width: 160, height: 160)
                    .cornerRadius(12)
                    .shadow(radius: 3)
            }
            
            // Info on right
            VStack(alignment: .leading, spacing: 8) {
                // Title and Author
                VStack(alignment: .leading, spacing: 2) {
                    Text(podcast.title)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    if let author = podcast.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Description
                if let description = podcast.podcastDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                
                // Metadata row
                HStack(spacing: 12) {
                    Label("\(podcast.episodes.count)", systemImage: "list.bullet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if let lastUpdated = podcast.lastUpdated {
                        Text("Updated \(lastUpdated, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Website link
                    if let websiteURL = podcast.websiteURL, let url = URL(string: websiteURL) {
                        Link(destination: url) {
                            Label("Web", systemImage: "safari")
                                .font(.caption2)
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onRefresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: onUnsubscribe) {
                        Label("Unsubscribe", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(.regularMaterial)
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
