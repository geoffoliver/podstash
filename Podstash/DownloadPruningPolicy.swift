//
//  DownloadPruningPolicy.swift
//  Podstash
//

import Foundation

/// Pure decision logic behind DownloadManager's two disk-cleanup passes, pulled out so the
/// cutoff/matching rules are testable without touching the real Downloads or temp directories.
enum DownloadPruningPolicy {
    /// Filenames in the Downloads directory eligible for deletion: not referenced by any Episode,
    /// and old enough that a fresh CloudKit import (e.g. right after Settings > Reset Local Sync,
    /// where the local store is briefly empty while episodes re-sync) can't race it and delete a
    /// file that's about to be legitimately re-linked.
    static func orphanedDownloadFilenames(
        files: [(filename: String, modificationDate: Date)],
        referencedFilenames: Set<String>,
        now: Date = .now,
        minimumAge: TimeInterval = 60 * 60 * 24
    ) -> Set<String> {
        let cutoff = now.addingTimeInterval(-minimumAge)
        return Set(files
            .filter { !referencedFilenames.contains($0.filename) && $0.modificationDate < cutoff }
            .map(\.filename))
    }

    /// ".tmp" files in the temp directory older than an hour - leftovers from a crash/force-quit
    /// before the app could finish processing or clean up after itself. Directories and anything
    /// without a ".tmp" extension are never eligible, so this can't touch unrelated subdirectories
    /// other frameworks use (e.g. AVFoundation's media cache).
    static func staleTempFilenames(
        files: [(filename: String, modificationDate: Date, isRegularFile: Bool)],
        now: Date = .now,
        minimumAge: TimeInterval = 60 * 60
    ) -> Set<String> {
        let cutoff = now.addingTimeInterval(-minimumAge)
        return Set(files
            .filter { $0.isRegularFile && ($0.filename as NSString).pathExtension == "tmp" && $0.modificationDate < cutoff }
            .map(\.filename))
    }
}
