//
//  StorageInfoPolicyTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("StorageInfoPolicy")
struct StorageInfoPolicyTests {

    // MARK: - totalBytes

    @Test("Sums actual downloaded file sizes rather than estimating from duration")
    func sumsFileSizes() {
        #expect(StorageInfoPolicy.totalBytes(downloadedFileSizes: [1_000, 2_000, 3_000]) == 6_000)
    }

    @Test("An episode downloaded but never played (duration unknown) still contributes its real file size")
    func nonZeroForUnplayedDownload() {
        // This is the regression case: a video download with no measured/parsed duration used to
        // report 0 MB because the old estimate was duration-based. A real file size is never 0.
        #expect(StorageInfoPolicy.totalBytes(downloadedFileSizes: [734_003_200]) == 734_003_200)
    }

    @Test("No downloads means zero bytes")
    func zeroForNoDownloads() {
        #expect(StorageInfoPolicy.totalBytes(downloadedFileSizes: []) == 0)
    }

    // MARK: - formattedSize

    @Test("Formats zero bytes as 0 MB")
    func formatsZero() {
        #expect(StorageInfoPolicy.formattedSize(bytes: 0) == "0 MB")
    }

    @Test("Formats a single downloaded video file's size in MB, not 0 MB")
    func formatsVideoFileSize() {
        // ~700 MB video file
        #expect(StorageInfoPolicy.formattedSize(bytes: 734_003_200) == "700 MB")
    }

    @Test("Switches to GB with one decimal place at 1024 MB and above")
    func formatsGB() {
        #expect(StorageInfoPolicy.formattedSize(bytes: 1_610_612_736) == "1.5 GB") // 1536 MB
    }
}
