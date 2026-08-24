//
//  NowPlayingView.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI
import AVKit

#if os(iOS) || os(tvOS)
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = .label
        routePickerView.prioritizesVideoDevices = false
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#elseif os(macOS)
struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        AVRoutePickerView()
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#else
struct AirPlayButton: View {
    var body: some View { EmptyView() }
}
#endif

struct NowPlayingView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var playbackProgress: PlaybackProgress
    
    var body: some View {
        if let episode = audioPlayer.currentEpisode {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    #if os(macOS)
                    Button {
                        audioPlayer.showMiniPlayer()
                    } label: {
                        Label("Mini Player", systemImage: "pip.enter")
                    }
                    .help("Open mini player window")
                    #endif
                    AirPlayButton()
                        .frame(width: 28, height: 28)
                }
                .padding()

                Spacer()

                // Episode artwork
                EpisodeThumbnail(episode: episode, podcast: audioPlayer.currentPodcast) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        )
                }
                .frame(width: 250, height: 250)
                .cornerRadius(12)
                .shadow(radius: 8)
                .id(episode.id)

                // Episode Info
                VStack(spacing: 8) {
                    Text(episode.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    if let podcast = audioPlayer.currentPodcast {
                        Text(podcast.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Progress Slider
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { playbackProgress.currentTime },
                            set: { audioPlayer.seek(to: $0) }
                        ),
                        in: 0...max(playbackProgress.duration, 1)
                    )
                    .padding(.horizontal)

                    HStack {
                        Text(formatTime(playbackProgress.currentTime))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(formatTime(playbackProgress.duration))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Playback Controls
                HStack(spacing: 40) {
                    // Skip Back 15s
                    Button {
                        audioPlayer.skip(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }

                    // Play/Pause
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }

                    // Skip Forward 30s
                    Button {
                        audioPlayer.skip(by: 30)
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.title)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding()
                
                // Playback Speed
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                        Button(action: {
                            audioPlayer.setPlaybackRate(Float(speed))
                        }) {
                            HStack {
                                Text("\(speed, specifier: "%.2f")x")
                                if playbackProgress.playbackRate == Float(speed) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "gauge")
                        Text("\(playbackProgress.playbackRate, specifier: "%.2f")x")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .cornerRadius(20)
                }
                
                Spacer()
            }
            .padding()
        } else {
            // Empty State
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)

                Text("No Episode Playing")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select an episode from your podcasts to start listening")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
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

// MARK: - Compact Player Bar (for iOS bottom bar)

#if !os(macOS)
extension View {
    // NavigationSplitView manages its own per-column safe areas, so the safeAreaInset
    // ContentView applies around the whole split view for CompactPlayerBar never reaches a
    // column's List content inset - every List in a sidebar/detail column (Queue, podcast
    // detail's episode list, the podcast sidebar) scrolls its last row half-hidden behind the
    // bar without this. Apply directly to each List; reserves the bar's actual measured height.
    func reservePlayerBarSpace(_ audioPlayer: AudioPlayerManager) -> some View {
        safeAreaInset(edge: .bottom) {
            if audioPlayer.currentEpisode != nil {
                Color.clear.frame(height: audioPlayer.progress.compactPlayerBarHeight)
            }
        }
    }
}
#endif

struct CompactPlayerBar: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var playbackProgress: PlaybackProgress
    @State private var showingNowPlaying = false

    var body: some View {
        if let episode = audioPlayer.currentEpisode {
            HStack(spacing: 12) {
                // Episode artwork thumbnail
                EpisodeThumbnail(episode: episode, podcast: audioPlayer.currentPodcast) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        )
                }
                .frame(width: 40, height: 40)
                .cornerRadius(6)
                .id(episode.id)

                // Episode Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let podcast = audioPlayer.currentPodcast {
                        Text(podcast.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // AirPlay Button
                AirPlayButton()
                    .frame(width: 24, height: 24)

                // Play/Pause Button
                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.regularMaterial)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                playbackProgress.compactPlayerBarHeight = height
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showingNowPlaying = true
            }
            .sheet(isPresented: $showingNowPlaying) {
                NavigationStack {
                    NowPlayingView()
                        .environmentObject(audioPlayer)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showingNowPlaying = false
                                }
                            }
                        }
                }
            }
        }
    }
}

#Preview {
    NowPlayingView()
        .environmentObject(AudioPlayerManager())
}
