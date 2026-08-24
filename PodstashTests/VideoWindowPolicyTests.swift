//
//  VideoWindowPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("VideoWindowPolicy")
struct VideoWindowPolicyTests {

    // MARK: - shouldOpenVideoWindow

    @Test("Opens the video window when the resolved/current kind is video and the window isn't already open")
    func opensWhenVideoAndClosed() {
        #expect(VideoWindowPolicy.shouldOpenVideoWindow(mediaKind: .video, isWindowOpen: false) == true)
    }

    @Test("Does not reopen the video window when it's already open")
    func doesNotReopenWhenAlreadyOpen() {
        #expect(VideoWindowPolicy.shouldOpenVideoWindow(mediaKind: .video, isWindowOpen: true) == false)
    }

    @Test("Never opens the video window for audio kind")
    func doesNotOpenForAudio() {
        #expect(VideoWindowPolicy.shouldOpenVideoWindow(mediaKind: .audio, isWindowOpen: false) == false)
        #expect(VideoWindowPolicy.shouldOpenVideoWindow(mediaKind: .audio, isWindowOpen: true) == false)
    }

    // MARK: - showOpenVideoButton

    @Test("Shows the Open Video button when the episode has a video enclosure and the window isn't open")
    func showsButtonWhenVideoAvailableAndClosed() {
        #expect(VideoWindowPolicy.showOpenVideoButton(hasVideoURL: true, isWindowOpen: false) == true)
    }

    @Test("Hides the Open Video button once the window is already open")
    func hidesButtonWhenWindowOpen() {
        #expect(VideoWindowPolicy.showOpenVideoButton(hasVideoURL: true, isWindowOpen: true) == false)
    }

    @Test("Hides the Open Video button when the episode has no video enclosure")
    func hidesButtonWhenNoVideoURL() {
        #expect(VideoWindowPolicy.showOpenVideoButton(hasVideoURL: false, isWindowOpen: false) == false)
    }

    // MARK: - closeAction

    @Test("Closing the video window falls back to audio when the episode has an audio enclosure")
    func closeSwitchesToAudioWhenAvailable() {
        #expect(VideoWindowPolicy.closeAction(hasAudioURL: true) == .pauseAndSwitchToAudio)
    }

    @Test("Closing the video window on a video-only episode just pauses, leaving mediaKind at .video")
    func closeOnVideoOnlyJustPauses() {
        #expect(VideoWindowPolicy.closeAction(hasAudioURL: false) == .pauseOnly)
    }
}
