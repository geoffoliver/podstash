//
//  VideoDisplayPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("VideoDisplayPolicy")
struct VideoDisplayPolicyTests {

    // MARK: - Video-only episode: no audio enclosure to switch to, so "Audio" just hides the frame

    @Test("Selecting Audio on a video-only episode hides the video frame instead of switching source")
    func videoOnlySelectingAudioHidesFrame() {
        let plan = VideoDisplayPolicy.plan(requestedKind: .audio, currentMediaKind: .video, hasAudioURL: false)
        #expect(plan == .setFrameVisible(false))
    }

    @Test("Re-selecting Video on a video-only episode after hiding it shows the frame again, without reloading")
    func videoOnlyReselectingVideoShowsFrame() {
        let plan = VideoDisplayPolicy.plan(requestedKind: .video, currentMediaKind: .video, hasAudioURL: false)
        #expect(plan == .setFrameVisible(true))
    }

    // MARK: - Mixed episode: a real audio enclosure exists, so the toggle performs an actual source switch

    @Test("Selecting Audio on a mixed episode switches the loaded source, same as before this feature")
    func mixedSelectingAudioSwitchesSource() {
        let plan = VideoDisplayPolicy.plan(requestedKind: .audio, currentMediaKind: .video, hasAudioURL: true)
        #expect(plan == .switchSource(to: .audio))
    }

    @Test("Selecting Video on a mixed episode currently playing audio switches the loaded source")
    func mixedSelectingVideoSwitchesSource() {
        let plan = VideoDisplayPolicy.plan(requestedKind: .video, currentMediaKind: .audio, hasAudioURL: true)
        #expect(plan == .switchSource(to: .video))
    }
}
