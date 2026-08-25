//
//  MediaKindPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("MediaKindPolicy")
struct MediaKindPolicyTests {

    // MARK: - resolvedDefaultKind

    @Test("Respects a stored defaultMediaKind even if it contradicts audioURL presence")
    func respectsStoredKind() {
        #expect(MediaKindPolicy.resolvedDefaultKind(defaultMediaKind: .video, hasAudioURL: true) == .video)
        #expect(MediaKindPolicy.resolvedDefaultKind(defaultMediaKind: .audio, hasAudioURL: false) == .audio)
    }

    @Test("Falls back to audio when defaultMediaKind is nil (pre-migration row) and audioURL is present")
    func fallsBackToAudioWhenNilAndAudioPresent() {
        #expect(MediaKindPolicy.resolvedDefaultKind(defaultMediaKind: nil, hasAudioURL: true) == .audio)
    }

    @Test("Falls back to video when defaultMediaKind is nil (pre-migration row) and audioURL is absent")
    func fallsBackToVideoWhenNilAndNoAudio() {
        #expect(MediaKindPolicy.resolvedDefaultKind(defaultMediaKind: nil, hasAudioURL: false) == .video)
    }

    // MARK: - urlString(for:audioURL:videoURL:)

    @Test("Audio kind resolves to audioURL, ignoring videoURL")
    func audioKindResolvesToAudioURL() {
        let url = MediaKindPolicy.urlString(for: .audio, audioURL: "https://example.com/a.mp3", videoURL: "https://example.com/a.mp4")
        #expect(url == "https://example.com/a.mp3")
    }

    @Test("Video kind resolves to videoURL, ignoring audioURL")
    func videoKindResolvesToVideoURL() {
        let url = MediaKindPolicy.urlString(for: .video, audioURL: "https://example.com/a.mp3", videoURL: "https://example.com/a.mp4")
        #expect(url == "https://example.com/a.mp4")
    }

    @Test("Requesting a kind the episode has no enclosure for resolves to nil")
    func missingEnclosureResolvesToNil() {
        #expect(MediaKindPolicy.urlString(for: .video, audioURL: "https://example.com/a.mp3", videoURL: nil) == nil)
        #expect(MediaKindPolicy.urlString(for: .audio, audioURL: nil, videoURL: "https://example.com/a.mp4") == nil)
    }

    // MARK: - switchPlan

    @Test("switchPlan refuses to switch to a kind the episode has no enclosure for")
    func switchPlanRefusesMissingKind() {
        let plan = MediaKindPolicy.switchPlan(
            to: .video,
            audioURL: "https://example.com/a.mp3",
            videoURL: nil,
            currentTime: 42,
            isPlaying: true,
            playbackRate: 1.0
        )
        #expect(plan == nil)
    }

    @Test("switchPlan carries the current position over as-is (seconds, not proportional)")
    func switchPlanCarriesOverPositionVerbatim() {
        let plan = MediaKindPolicy.switchPlan(
            to: .video,
            audioURL: "https://example.com/a.mp3",
            videoURL: "https://example.com/a.mp4",
            currentTime: 123.5,
            isPlaying: true,
            playbackRate: 1.5
        )
        #expect(plan?.kind == .video)
        #expect(plan?.urlString == "https://example.com/a.mp4")
        #expect(plan?.seekTo == 123.5)
        #expect(plan?.shouldAutoplay == true)
        #expect(plan?.playbackRate == 1.5)
    }

    @Test("switchPlan preserves a paused state rather than forcing playback")
    func switchPlanPreservesPausedState() {
        let plan = MediaKindPolicy.switchPlan(
            to: .audio,
            audioURL: "https://example.com/a.mp3",
            videoURL: "https://example.com/a.mp4",
            currentTime: 10,
            isPlaying: false,
            playbackRate: 1.0
        )
        #expect(plan?.shouldAutoplay == false)
    }

    // MARK: - MediaSwitchPlan.effectiveRate

    @Test("effectiveRate is the carried-over playback rate when the plan should autoplay")
    func effectiveRateIsPlaybackRateWhenAutoplaying() {
        let plan = MediaSwitchPlan(kind: .audio, urlString: "https://example.com/a.mp3", seekTo: 10, shouldAutoplay: true, playbackRate: 1.5)
        #expect(plan.effectiveRate == 1.5)
    }

    @Test("effectiveRate is zero when the plan should not autoplay, regardless of playbackRate - AVPlayer.rate must never go nonzero for a paused switch, or it silently starts playing")
    func effectiveRateIsZeroWhenNotAutoplaying() {
        let plan = MediaSwitchPlan(kind: .audio, urlString: "https://example.com/a.mp3", seekTo: 10, shouldAutoplay: false, playbackRate: 1.5)
        #expect(plan.effectiveRate == 0)
    }

    // MARK: - downloadURLString

    @Test("Downloads the audio enclosure for a mixed episode, matching what plays by default")
    func downloadPrefersAudioForMixedEpisode() {
        let url = MediaKindPolicy.downloadURLString(
            defaultMediaKind: .audio,
            audioURL: "https://example.com/a.mp3",
            videoURL: "https://example.com/a.mp4"
        )
        #expect(url == "https://example.com/a.mp3")
    }

    @Test("Downloads the video enclosure for a video-only episode, instead of silently no-oping")
    func downloadFallsBackToVideoForVideoOnlyEpisode() {
        let url = MediaKindPolicy.downloadURLString(
            defaultMediaKind: .video,
            audioURL: nil,
            videoURL: "https://example.com/a.mp4"
        )
        #expect(url == "https://example.com/a.mp4")
    }

    @Test("downloadURLString falls back to resolvedDefaultKind when defaultMediaKind is nil (pre-migration row)")
    func downloadResolvesNilDefaultMediaKind() {
        let url = MediaKindPolicy.downloadURLString(
            defaultMediaKind: nil,
            audioURL: nil,
            videoURL: "https://example.com/a.mp4"
        )
        #expect(url == "https://example.com/a.mp4")
    }

    // MARK: - shouldUseLocalFile

    @Test("A downloaded mixed episode's local file matches the default (audio) kind")
    func localFileMatchesDefaultKindForMixedEpisode() {
        #expect(MediaKindPolicy.shouldUseLocalFile(requestedKind: .audio, defaultMediaKind: .audio, hasAudioURL: true) == true)
    }

    @Test("A downloaded mixed episode's local file does NOT satisfy a request for the non-default kind")
    func localFileDoesNotMatchNonDefaultKindForMixedEpisode() {
        // The on-disk file is always the default-kind download (see downloadURLString) - a
        // user switching a mixed episode to video shouldn't be handed the downloaded audio file.
        #expect(MediaKindPolicy.shouldUseLocalFile(requestedKind: .video, defaultMediaKind: .audio, hasAudioURL: true) == false)
    }

    @Test("A downloaded video-only episode's local file matches a request for video")
    func localFileMatchesVideoOnlyEpisode() {
        #expect(MediaKindPolicy.shouldUseLocalFile(requestedKind: .video, defaultMediaKind: .video, hasAudioURL: false) == true)
    }
}
