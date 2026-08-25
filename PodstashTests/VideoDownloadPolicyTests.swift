//
//  VideoDownloadPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("VideoDownloadPolicy")
struct VideoDownloadPolicyTests {

    // MARK: - Audio downloads are never gated by the Wi-Fi-only-for-video setting

    @Test("Audio download proceeds on cellular even when the Wi-Fi-only setting is on")
    func audioDownloadProceedsOnCellularWithSettingOn() {
        let shouldDownload = VideoDownloadPolicy.shouldDownloadNow(
            mediaKind: .audio,
            downloadVideoOnWiFiOnly: true,
            isOnWiFi: false
        )
        #expect(shouldDownload == true)
    }

    @Test("Audio download proceeds on Wi-Fi with the setting on")
    func audioDownloadProceedsOnWiFiWithSettingOn() {
        let shouldDownload = VideoDownloadPolicy.shouldDownloadNow(
            mediaKind: .audio,
            downloadVideoOnWiFiOnly: true,
            isOnWiFi: true
        )
        #expect(shouldDownload == true)
    }

    // MARK: - Video downloads are gated only when the setting is on AND not on Wi-Fi

    @Test("Video download proceeds on Wi-Fi with the setting on")
    func videoDownloadProceedsOnWiFiWithSettingOn() {
        let shouldDownload = VideoDownloadPolicy.shouldDownloadNow(
            mediaKind: .video,
            downloadVideoOnWiFiOnly: true,
            isOnWiFi: true
        )
        #expect(shouldDownload == true)
    }

    @Test("Video download is blocked on cellular with the setting on")
    func videoDownloadBlockedOnCellularWithSettingOn() {
        let shouldDownload = VideoDownloadPolicy.shouldDownloadNow(
            mediaKind: .video,
            downloadVideoOnWiFiOnly: true,
            isOnWiFi: false
        )
        #expect(shouldDownload == false)
    }

    @Test("Video download proceeds on cellular when the setting is off")
    func videoDownloadProceedsOnCellularWithSettingOff() {
        let shouldDownload = VideoDownloadPolicy.shouldDownloadNow(
            mediaKind: .video,
            downloadVideoOnWiFiOnly: false,
            isOnWiFi: false
        )
        #expect(shouldDownload == true)
    }

    @Test("Video download proceeds on Wi-Fi when the setting is off")
    func videoDownloadProceedsOnWiFiWithSettingOff() {
        let shouldDownload = VideoDownloadPolicy.shouldDownloadNow(
            mediaKind: .video,
            downloadVideoOnWiFiOnly: false,
            isOnWiFi: true
        )
        #expect(shouldDownload == true)
    }

    // MARK: - shouldAutoDownload: auto-download (FeedFetcher's post-refresh pass) skips video by
    // default, since a burst of new video episodes could eat a lot of storage unattended. Manual
    // "download this episode" taps never call through this function, so they're unaffected.

    @Test("Audio episodes are always included in auto-download, regardless of the video opt-in")
    func audioAlwaysAutoDownloads() {
        #expect(VideoDownloadPolicy.shouldAutoDownload(mediaKind: .audio, autoDownloadVideoEpisodes: false) == true)
        #expect(VideoDownloadPolicy.shouldAutoDownload(mediaKind: .audio, autoDownloadVideoEpisodes: true) == true)
    }

    @Test("Video episodes are excluded from auto-download unless the user has opted in")
    func videoAutoDownloadRequiresOptIn() {
        #expect(VideoDownloadPolicy.shouldAutoDownload(mediaKind: .video, autoDownloadVideoEpisodes: false) == false)
        #expect(VideoDownloadPolicy.shouldAutoDownload(mediaKind: .video, autoDownloadVideoEpisodes: true) == true)
    }
}
