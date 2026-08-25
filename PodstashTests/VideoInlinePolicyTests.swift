//
//  VideoInlinePolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("VideoInlinePolicy")
struct VideoInlinePolicyTests {

    // MARK: - showMediaKindToggle

    @Test("Shows the Audio/Video toggle when the episode has both enclosures")
    func showsToggleWhenBothEnclosuresPresent() {
        #expect(VideoInlinePolicy.showMediaKindToggle(hasVideoURL: true) == true)
    }

    @Test("Hides the toggle for an audio-only episode")
    func hidesToggleForAudioOnly() {
        #expect(VideoInlinePolicy.showMediaKindToggle(hasVideoURL: false) == false)
    }

    @Test("Still shows the toggle for a video-only episode, so the user can hide the video frame and listen audio-only")
    func showsToggleForVideoOnly() {
        #expect(VideoInlinePolicy.showMediaKindToggle(hasVideoURL: true) == true)
    }

    // MARK: - shouldEnableVideoTrack

    @Test("Enables the video track when playing video, app active, Now Playing surface visible, and the video frame is what the user wants to see")
    func enablesWhenAllConditionsMet() {
        #expect(VideoInlinePolicy.shouldEnableVideoTrack(mediaKind: .video, isAppActive: true, isNowPlayingSurfaceVisible: true, isVideoFrameVisible: true) == true)
    }

    @Test("Disables the video track while backgrounded, even if the Now Playing surface was left visible")
    func disablesWhenAppBackgrounded() {
        #expect(VideoInlinePolicy.shouldEnableVideoTrack(mediaKind: .video, isAppActive: false, isNowPlayingSurfaceVisible: true, isVideoFrameVisible: true) == false)
    }

    @Test("Disables the video track when the Now Playing surface isn't visible, even if the app is active")
    func disablesWhenNowPlayingSurfaceNotVisible() {
        #expect(VideoInlinePolicy.shouldEnableVideoTrack(mediaKind: .video, isAppActive: true, isNowPlayingSurfaceVisible: false, isVideoFrameVisible: true) == false)
    }

    @Test("Never enables the video track for an audio-kind item")
    func disablesForAudioKind() {
        #expect(VideoInlinePolicy.shouldEnableVideoTrack(mediaKind: .audio, isAppActive: true, isNowPlayingSurfaceVisible: true, isVideoFrameVisible: true) == false)
    }

    @Test("Disables the video track when the user has chosen the audio-only display for a video-only episode, even though the app is active and Now Playing is visible")
    func disablesWhenUserHidesTheFrame() {
        #expect(VideoInlinePolicy.shouldEnableVideoTrack(mediaKind: .video, isAppActive: true, isNowPlayingSurfaceVisible: true, isVideoFrameVisible: false) == false)
    }
}
