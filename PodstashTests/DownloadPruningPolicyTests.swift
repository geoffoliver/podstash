//
//  DownloadPruningPolicyTests.swift
//  PodstashTests
//

import Testing
import Foundation
@testable import Podstash

@Suite("DownloadPruningPolicy")
struct DownloadPruningPolicyTests {

    // MARK: - orphanedDownloadFilenames

    @Test("A file with no matching Episode is orphaned once past the minimum age")
    func unreferencedOldFileIsOrphaned() {
        let now = Date.now
        let orphaned = DownloadPruningPolicy.orphanedDownloadFilenames(
            files: [(filename: "gone.mp3", modificationDate: now.addingTimeInterval(-2 * 86400))],
            referencedFilenames: [],
            now: now
        )
        #expect(orphaned == ["gone.mp3"])
    }

    @Test("A file still referenced by an Episode is never orphaned, regardless of age")
    func referencedFileIsNeverOrphaned() {
        let now = Date.now
        let orphaned = DownloadPruningPolicy.orphanedDownloadFilenames(
            files: [(filename: "keep.mp3", modificationDate: now.addingTimeInterval(-30 * 86400))],
            referencedFilenames: ["keep.mp3"],
            now: now
        )
        #expect(orphaned.isEmpty)
    }

    @Test("An unreferenced file younger than the minimum age is kept, to avoid racing a fresh CloudKit import")
    func recentUnreferencedFileIsKept() {
        let now = Date.now
        let orphaned = DownloadPruningPolicy.orphanedDownloadFilenames(
            files: [(filename: "new.mp3", modificationDate: now.addingTimeInterval(-60))],
            referencedFilenames: [],
            now: now
        )
        #expect(orphaned.isEmpty)
    }

    // MARK: - staleTempFilenames

    @Test("A .tmp file older than an hour is stale")
    func oldTmpFileIsStale() {
        let now = Date.now
        let stale = DownloadPruningPolicy.staleTempFilenames(
            files: [(filename: "CFNetworkDownload_1.tmp", modificationDate: now.addingTimeInterval(-2 * 3600), isRegularFile: true)],
            now: now
        )
        #expect(stale == ["CFNetworkDownload_1.tmp"])
    }

    @Test("A recent .tmp file is kept")
    func recentTmpFileIsKept() {
        let now = Date.now
        let stale = DownloadPruningPolicy.staleTempFilenames(
            files: [(filename: "fresh.tmp", modificationDate: now.addingTimeInterval(-60), isRegularFile: true)],
            now: now
        )
        #expect(stale.isEmpty)
    }

    @Test("A non-.tmp file is never considered, regardless of age")
    func nonTmpFileIsIgnored() {
        let now = Date.now
        let stale = DownloadPruningPolicy.staleTempFilenames(
            files: [(filename: "episode.mp3", modificationDate: now.addingTimeInterval(-2 * 3600), isRegularFile: true)],
            now: now
        )
        #expect(stale.isEmpty)
    }

    @Test("A directory named *.tmp is never considered, even when old")
    func tmpDirectoryIsIgnored() {
        let now = Date.now
        let stale = DownloadPruningPolicy.staleTempFilenames(
            files: [(filename: "SomeCache.tmp", modificationDate: now.addingTimeInterval(-2 * 3600), isRegularFile: false)],
            now: now
        )
        #expect(stale.isEmpty)
    }
}
