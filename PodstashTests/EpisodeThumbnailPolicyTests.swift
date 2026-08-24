//
//  EpisodeThumbnailPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("EpisodeThumbnailPolicy")
struct EpisodeThumbnailPolicyTests {

    // MARK: - resolvedArtworkURLString

    @Test("Prefers episode artwork over podcast artwork when both are present")
    func prefersEpisodeArtwork() {
        let url = EpisodeThumbnailPolicy.resolvedArtworkURLString(
            episodeArtworkURL: "https://example.com/episode.jpg",
            podcastArtworkURL: "https://example.com/podcast.jpg"
        )
        #expect(url == "https://example.com/episode.jpg")
    }

    @Test("Falls back to podcast artwork when episode artwork is nil")
    func fallsBackToPodcastArtwork() {
        let url = EpisodeThumbnailPolicy.resolvedArtworkURLString(
            episodeArtworkURL: nil,
            podcastArtworkURL: "https://example.com/podcast.jpg"
        )
        #expect(url == "https://example.com/podcast.jpg")
    }

    @Test("Resolves to nil when neither episode nor podcast artwork is present")
    func nilWhenBothMissing() {
        let url = EpisodeThumbnailPolicy.resolvedArtworkURLString(episodeArtworkURL: nil, podcastArtworkURL: nil)
        #expect(url == nil)
    }

    // MARK: - showsVideoBadge

    @Test("Shows the video badge when the episode has a video enclosure")
    func showsBadgeWhenVideoPresent() {
        #expect(EpisodeThumbnailPolicy.showsVideoBadge(videoURL: "https://example.com/a.mp4") == true)
    }

    @Test("Hides the video badge when the episode has no video enclosure")
    func hidesBadgeWhenVideoMissing() {
        #expect(EpisodeThumbnailPolicy.showsVideoBadge(videoURL: nil) == false)
    }
}
