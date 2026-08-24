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
        ZStack(alignment: .bottomTrailing) {
            CachedAsyncImage(
                url: resolvedURL,
                content: { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                },
                placeholder: placeholder
            )

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
