//
//  FloatingPlayerBar.swift
//  Podstash
//
//  A floating "mini player" overlay mirroring Apple Podcasts: an inset rounded card (iOS) /
//  stadium pill (macOS) with margins and a shadow, floating over content rather than reserving
//  its own layout row. Always visible - when nothing is loaded it shows a disabled "Nothing
//  Playing" placeholder instead of disappearing (see FloatingPlayerPolicy).
//

import SwiftUI
import AVKit

#if os(macOS)
struct AirPlayRoutePickerView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif

struct FloatingPlayerBar: View {
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @EnvironmentObject var playbackProgress: PlaybackProgress
    @EnvironmentObject var refreshCoordinator: RefreshCoordinator
    @State private var showingNowPlaying = false
    #if os(macOS)
    @State private var hoveringOverArt = false
    #endif

    private var hasEpisode: Bool { audioPlayer.currentEpisode != nil }
    private var controlsEnabled: Bool { FloatingPlayerPolicy.controlsEnabled(hasCurrentEpisode: hasEpisode) }
    private var refreshBarVisible: Bool { refreshCoordinator.isRefreshing || refreshCoordinator.refreshCompleted != nil }

    private var baseBottomMargin: CGFloat {
        #if os(macOS)
        12
        #else
        0
        #endif
    }

    // On macOS, RefreshStatusBar reserves its own VStack row below the NavigationSplitView (see
    // ContentView), so it structurally can't overlap this bar's detail-column overlay - no
    // clearance needed there. On iOS, RefreshStatusBar docks via `.safeAreaInset` instead, which
    // doesn't shrink the column's own frame (see RefreshCoordinator.statusBarHeight's doc
    // comment), so this bar has to explicitly clear it.
    private var bottomMargin: CGFloat {
        #if os(macOS)
        baseBottomMargin
        #else
        FloatingPlayerPolicy.bottomMargin(
            baseMargin: baseBottomMargin,
            gap: 8,
            refreshBarVisible: refreshBarVisible,
            refreshBarHeight: refreshCoordinator.statusBarHeight
        )
        #endif
    }

    var body: some View {
        #if os(macOS)
        macOSBar
        #else
        iOSBar
        #endif
    }

    private var placeholderArt: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - iOS (rounded-rect card)

    #if !os(macOS)
    private var iOSBar: some View {
        HStack(spacing: 12) {
            Group {
                if let episode = audioPlayer.currentEpisode {
                    EpisodeThumbnail(episode: episode, podcast: audioPlayer.currentPodcast) {
                        placeholderArt
                    }
                    .id(episode.id)
                } else {
                    placeholderArt
                }
            }
            .frame(width: 44, height: 44)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(audioPlayer.currentEpisode?.title ?? "Not Playing")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if hasEpisode, let podcast = audioPlayer.currentPodcast {
                    Text(podcast.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    audioPlayer.skipForward()
                } label: {
                    Image(systemName: "goforward")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .disabled(!controlsEnabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, bottomMargin)
        .contentShape(Rectangle())
        .onTapGesture {
            guard controlsEnabled else { return }
            showingNowPlaying = true
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            playbackProgress.floatingPlayerBarHeight = height
        }
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView()
                .environmentObject(audioPlayer)
                .presentationDragIndicator(.visible)
        }
        .animation(.default, value: hasEpisode)
    }
    #endif

    // MARK: - macOS (stadium pill)

    #if os(macOS)
    @State private var dragProgress: Double?

    private var progressFraction: Double {
        // While actively dragging, the bar follows the drag position rather than live playback
        // progress - otherwise it'd fight the scrub gesture as currentTime keeps ticking forward
        // underneath it.
        if let dragProgress { return dragProgress }
        guard playbackProgress.duration > 0 else { return 0 }
        return min(playbackProgress.currentTime / playbackProgress.duration, 1)
    }

    private var macOSBar: some View {
        HStack(spacing: 14) {
            Group {
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                        Button {
                            audioPlayer.setPlaybackRate(Float(speed))
                        } label: {
                            HStack {
                                Text("\(speed, specifier: "%.2f")x")
                                if abs(playbackProgress.playbackRate - Float(speed)) < 0.01 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(playbackProgress.playbackRate, specifier: "%.2f")x")
                        .font(.appFootnote)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    audioPlayer.skipBackward()
                } label: {
                    Image(systemName: "gobackward")
                        .font(.system(size: 16))
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Skip backward")

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(audioPlayer.isPlaying ? "Pause" : "Play")

                Button {
                    audioPlayer.skipForward()
                } label: {
                    Image(systemName: "goforward")
                        .font(.system(size: 16))
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Skip forward")
            }
            .disabled(!controlsEnabled)

            Group {
                if let episode = audioPlayer.currentEpisode,
                   let podcast = audioPlayer.currentPodcast,
                   podcast.artworkURL != nil {
                    EpisodeThumbnail(artworkURLString: podcast.artworkURL, videoURL: episode.videoURL) {
                        Color.gray.opacity(0.2)
                    }
                    .id(episode.id)
                    .shadow(color: .black.opacity(hoveringOverArt ? 0.4 : 0), radius: 3, x: 0, y: 0)
                    .brightness(hoveringOverArt ? 0.05 : 0)
                    .help(Text("Click to open Mini Player"))
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveringOverArt = hovering
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    .onTapGesture {
                        MenuCoordinator.shared.audioPlayer?.showMiniPlayer()
                    }
                } else {
                    placeholderArt
                }
            }
            .frame(width: 36, height: 36)
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 3) {
                Text(audioPlayer.currentEpisode?.title ?? "Not Playing")
                    .font(.appSubheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if hasEpisode {
                    if let podcast = audioPlayer.currentPodcast {
                        Text(podcast.title)
                            .font(.appFootnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Thin seekable progress line under the title, matching Apple Podcasts'
                    // compact mini-player - no numeric time labels here (those live in
                    // MiniPlayerWindow's full player). The drawn line and its own layout frame
                    // stay thin (3pt) so it doesn't push the title out of alignment with the
                    // artwork - only the hit-testing region is expanded, via a negative-inset
                    // contentShape rather than a taller frame, so the larger drag target doesn't
                    // affect layout at all. Driven by a real DragGesture rather than
                    // onTapGesture - a tap-only, exactly-as-tall-as-the-line hit target is nearly
                    // impossible to land a click on.
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.25)).frame(height: 3)
                            Capsule().fill(Color.accentColor).frame(width: geometry.size.width * CGFloat(progressFraction), height: 3)
                        }
                        .contentShape(Rectangle().inset(by: -5))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragProgress = max(0, min(1, value.location.x / geometry.size.width))
                                }
                                .onEnded { value in
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    audioPlayer.seek(to: playbackProgress.duration * Double(progress))
                                    dragProgress = nil
                                }
                        )
                    }
                    .frame(height: 3)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let episode = audioPlayer.currentEpisode,
               VideoWindowPolicy.showOpenVideoButton(hasVideoURL: episode.videoURL != nil, isWindowOpen: audioPlayer.isVideoWindowOpen) {
                // Blue-highlighted, not just another plain icon in the gray cluster - this is
                // the only way to reopen the video window once it's been closed, so it needs to
                // actually be noticed rather than blend in.
                Button {
                    audioPlayer.openVideo()
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.blue))
                }
                .buttonStyle(.plain)
                .help("Open Video")
            }

            AirPlayRoutePickerView()
                .frame(width: 24, height: 24)
                .help("AirPlay")
                .disabled(!controlsEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, baseBottomMargin)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            playbackProgress.floatingPlayerBarHeight = height
        }
        .animation(.default, value: hasEpisode)
    }
    #endif
}
