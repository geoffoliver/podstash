//
//  NowPlayingView.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import SwiftUI
import SwiftData
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
    @Environment(\.modelContext) private var modelContext
    @State private var isFullscreenPresented = false
    @State private var showingTimeRemaining = false

    var body: some View {
        if let episode = audioPlayer.currentEpisode {
            #if os(macOS)
            macOSPlayerBody(episode: episode)
            #else
            iOSPlayerBody(episode: episode)
                .onAppear { audioPlayer.setNowPlayingSurfaceVisible(true) }
                .onDisappear { audioPlayer.setNowPlayingSurfaceVisible(false) }
                .fullScreenCover(isPresented: $isFullscreenPresented) {
                    FullscreenVideoPlayerView(player: audioPlayer.playerForVideoSurface)
                        .ignoresSafeArea()
                }
            #endif
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
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

    // MARK: - iOS (Apple Podcasts-style full screen player)

    #if !os(macOS)
    private func iOSPlayerBody(episode: Episode) -> some View {
        GeometryReader { proxy in
            let artworkWidth = max(proxy.size.width - 88, 0)

            ZStack {
                backdrop(episode: episode, size: proxy.size)

                // No flexible Spacers here on purpose - this VStack hugs its natural content
                // size and ZStack's default center alignment splits any leftover height evenly
                // above/below. An earlier version used multiple Spacer(minLength:) elements to
                // fill the sheet's full height, but their split wasn't even in practice (likely
                // because the nested GeometryReader inside EpisodeThumbnail confuses the VStack's
                // flexibility calculation), which dumped nearly all the slack into one gap
                // between the transport controls and the volume row.
                VStack(spacing: 0) {
                    artworkOrVideoSurface(episode: episode, availableWidth: artworkWidth)
                        .id(episode.id)

                    if VideoInlinePolicy.showMediaKindToggle(hasVideoURL: episode.videoURL != nil) {
                        Picker("Media", selection: Binding(
                            get: { (audioPlayer.currentMediaKind == .video && audioPlayer.isVideoFrameVisible) ? MediaKind.video : .audio },
                            set: { audioPlayer.setDisplayMediaKind($0) }
                        )) {
                            Text("Audio").tag(MediaKind.audio)
                            Text("Video").tag(MediaKind.video)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 16)
                    }

                    episodeInfoRow(episode: episode)
                        .padding(.top, 28)

                    progressSection
                        .padding(.top, 20)

                    transportControlsRow
                        .padding(.top, 28)

                    bottomIconsRow
                        .padding(.top, 28)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    private func backdrop(episode: Episode, size: CGSize) -> some View {
        EpisodeThumbnail(episode: episode, podcast: audioPlayer.currentPodcast) {
            Color.gray.opacity(0.3)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .blur(radius: 50, opaque: true)
        // A Material, not a fixed black gradient - materials adapt automatically between light
        // and dark system appearance, so the backdrop keeps an artwork-tinted ambiance without
        // permanently forcing a dark look the way a hardcoded black scrim would.
        .overlay(.regularMaterial)
        .ignoresSafeArea()
    }

    private func artworkOrVideoSurface(episode: Episode, availableWidth: CGFloat) -> some View {
        Group {
            if audioPlayer.currentMediaKind == .video && audioPlayer.isVideoFrameVisible {
                VideoPlayerSurface(player: audioPlayer.playerForVideoSurface)
                    .frame(width: availableWidth, height: availableWidth * 9.0 / 16.0)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            isFullscreenPresented = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.body)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .padding(8)
                    }
                    // Always white-on-black, not adaptive - this button sits directly on top of
                    // the video image itself (not the backdrop scrim), which is arbitrary footage
                    // rather than something that tracks system appearance.
            } else {
                EpisodeThumbnail(episode: episode, podcast: audioPlayer.currentPodcast) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        )
                }
                .frame(width: availableWidth, height: availableWidth)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            }
        }
    }

    private func episodeInfoRow(episode: Episode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.publishDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(episode.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let podcast = audioPlayer.currentPodcast {
                    Text(podcast.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    markAsPlayed(episode)
                } label: {
                    Label("Mark as Played", systemImage: "checkmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.1), in: Circle())
            }
        }
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { playbackProgress.currentTime },
                    set: { audioPlayer.seek(to: $0) }
                ),
                in: 0...max(playbackProgress.duration, 1)
            )
            .tint(.primary)

            HStack {
                Text(PlaybackTimeDisplayPolicy.elapsedLabel(
                    currentTime: playbackProgress.currentTime,
                    duration: playbackProgress.duration,
                    showingRemaining: showingTimeRemaining
                ))
                    .contentShape(Rectangle())
                    .onTapGesture { showingTimeRemaining.toggle() }

                Spacer()

                Text(PlaybackTimeDisplayPolicy.elapsedLabel(
                    currentTime: playbackProgress.currentTime,
                    duration: playbackProgress.duration,
                    showingRemaining: true
                ))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var transportControlsRow: some View {
        HStack {
            speedButton
                .frame(width: 44, alignment: .leading)

            Spacer()

            HStack(spacing: 36) {
                rewindButton
                playPauseButton
                forwardButton
            }

            Spacer()

            Color.clear.frame(width: 44, height: 1)
        }
    }

    private var speedButton: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                Button {
                    audioPlayer.setPlaybackRate(Float(speed))
                } label: {
                    HStack {
                        Text("\(speed, specifier: "%.2f")x")
                        if playbackProgress.playbackRate == Float(speed) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text("\(playbackProgress.playbackRate, specifier: "%g")×")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        // Menu tints its label with the system accent color regardless of foregroundStyle on
        // the label content - .tint here is what actually overrides that to match the neutral
        // primary/secondary palette the rest of this screen uses.
        .tint(.primary)
    }

    private var rewindButton: some View {
        Button {
            audioPlayer.skipBackward()
        } label: {
            Image(systemName: "gobackward")
                .font(.system(size: 26))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var playPauseButton: some View {
        Button {
            audioPlayer.togglePlayPause()
        } label: {
            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 38))
                .foregroundStyle(.primary)
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var forwardButton: some View {
        Button {
            audioPlayer.skipForward()
        } label: {
            Image(systemName: "goforward")
                .font(.system(size: 26))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomIconsRow: some View {
        HStack {
            Spacer()
            AirPlayButton()
                .frame(width: 28, height: 28)
            Spacer()
        }
    }

    private func markAsPlayed(_ episode: Episode) {
        let record = PlaybackRecordStore.markPlayed(episode: episode, in: modelContext)
        record.queuePosition = nil
        record.playbackPosition = 0
        try? modelContext.save()
    }
    #endif

    // MARK: - macOS (legacy panel layout; NowPlayingView is unreachable from the macOS UI today
    // - Queue is the default detail view - but this keeps the type compiling with a sane, if
    // simpler, layout should that change.)

    #if os(macOS)
    private func macOSPlayerBody(episode: Episode) -> some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button {
                    audioPlayer.showMiniPlayer()
                } label: {
                    Label("Mini Player", systemImage: "pip.enter")
                }
                .help("Open mini player window")
                AirPlayButton()
                    .frame(width: 28, height: 28)
            }
            .padding()

            Spacer()

            episodeThumbnail(episode: episode)
                .id(episode.id)

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
                    Text(PlaybackTimeDisplayPolicy.elapsedLabel(
                        currentTime: playbackProgress.currentTime,
                        duration: playbackProgress.duration,
                        showingRemaining: showingTimeRemaining
                    ))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture { showingTimeRemaining.toggle() }

                    Spacer()

                    Text(PlaybackTimeDisplayPolicy.format(playbackProgress.duration))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 40) {
                Button {
                    audioPlayer.skipBackward()
                } label: {
                    Image(systemName: "gobackward")
                        .font(.title)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }

                Button {
                    audioPlayer.skipForward()
                } label: {
                    Image(systemName: "goforward")
                        .font(.title)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding()

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                    Button {
                        audioPlayer.setPlaybackRate(Float(speed))
                    } label: {
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
    }
    #endif

    private func episodeThumbnail(episode: Episode) -> some View {
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
    }
}

// MARK: - Reserve space for FloatingPlayerBar

extension View {
    // FloatingPlayerBar is a floating overlay (not layout-reserving), and on iOS
    // NavigationSplitView manages its own per-column safe areas - a safeAreaInset applied around
    // the whole split view never reaches a column's List content inset. Every List in a sidebar/
    // detail column (Queue, podcast detail's episode list, the podcast sidebar) needs this applied
    // directly so its last row can scroll fully clear of the bar. The bar is always shown (even
    // as a disabled "Nothing Playing" placeholder - see FloatingPlayerPolicy), so this always
    // reserves space rather than only when an episode is loaded.
    func reservePlayerBarSpace(_ audioPlayer: AudioPlayerManager) -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: audioPlayer.progress.floatingPlayerBarHeight)
        }
    }
}

#Preview {
    NowPlayingView()
        .environmentObject(AudioPlayerManager())
}
