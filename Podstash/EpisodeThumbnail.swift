//
//  EpisodeThumbnail.swift
//  Podstash
//

import SwiftUI

/// Shared wrapper around `CachedAsyncImage` for episode/podcast artwork, adding a video badge
/// overlay when the episode has a video enclosure. See VIDEO_PLAYBACK_PLAN.md Phase 3.
///
/// Callers own frame/cornerRadius/shadow exactly as they did with the ad hoc `CachedAsyncImage`
/// call sites this replaces - only the image + badge composition is centralized here, since sizes,
/// content modes, and placeholders vary too much across call sites to standardize.
struct EpisodeThumbnail<Placeholder: View>: View {
    var artworkURLString: String?
    var videoURL: String?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    /// Convenience for the common case: episode-specific artwork falling back to the podcast's,
    /// and the badge driven by whether the episode has a video enclosure.
    init(
        episode: Episode,
        podcast: Podcast?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.artworkURLString = EpisodeThumbnailPolicy.resolvedArtworkURLString(
            episodeArtworkURL: episode.artworkURL,
            podcastArtworkURL: podcast?.artworkURL
        )
        self.videoURL = episode.videoURL
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    /// Base initializer for sites with no single Episode to resolve artwork/badge from (e.g. a
    /// podcast-only header or list row) or that need to pick the artwork URL themselves.
    init(
        artworkURLString: String?,
        videoURL: String? = nil,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.artworkURLString = artworkURLString
        self.videoURL = videoURL
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    private var resolvedURL: URL? {
        artworkURLString.flatMap { URL(string: $0) }
    }

    private var showsVideoBadge: Bool {
        EpisodeThumbnailPolicy.showsVideoBadge(videoURL: videoURL)
    }

    var body: some View {
        // GeometryReader, not a bare ZStack - every call site wraps this in an explicit
        // .frame(width:height:) (see the doc comment above), so this always receives a firm,
        // unambiguous proposal to relay, not the "ideal size" ambiguity that GeometryReader runs
        // into when a parent's own size is still being negotiated (e.g. NowPlayingView's video
        // surface). Without it, a .fill-mode image whose source aspect ratio isn't square renders
        // *larger* than the frame in one dimension to cover it, which inflates the ZStack's own
        // layout frame - and the bottomTrailing-aligned video badge then gets positioned against
        // that inflated frame instead of the visible (clipped) square, so it can render partially
        // or entirely outside the thumbnail. Explicitly framing + clipping the image to the
        // measured size keeps the ZStack's frame (and the badge's alignment) sane regardless of
        // the source image's aspect ratio.
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(
                    url: resolvedURL,
                    content: { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    },
                    placeholder: placeholder
                )
                .frame(width: geometry.size.width, height: geometry.size.height)

                if showsVideoBadge {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(4)
                }
            }
        }
    }
}
