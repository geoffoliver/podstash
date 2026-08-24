//
//  DownloadManager.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published var activeDownloads: [UUID: Double] = [:] // Episode ID -> Progress (0.0 to 1.0)
    
    private var modelContext: ModelContext?
    private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]
    private var urlSession: URLSession!

    // Capped low on purpose: a burst of auto-downloads used to fire every task at once, each
    // completion doing its own SwiftData fetch+save on the main actor - with enough of them
    // landing in the same window, that stalled the UI for ~20s. Queuing the rest keeps the app
    // responsive at the cost of some throughput.
    private let maxConcurrentDownloads = 3
    private var pendingDownloadQueue: [Episode] = []
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func isDownloading(_ episode: Episode) -> Bool {
        return activeDownloads[episode.id] != nil
    }

    func downloadProgress(for episode: Episode) -> Double? {
        return activeDownloads[episode.id]
    }

    /// Directory downloaded episode audio lives in on this device.
    static var downloadsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Resolves a filename stored in `Episode.downloadedFilename` to this device's local file
    /// URL. Only the filename syncs via iCloud (it's deterministic, derived from the episode's
    /// id) - never an absolute path, since each device's container path is different.
    static func localFileURL(forStoredFilename filename: String) -> URL {
        downloadsDirectory.appendingPathComponent(filename)
    }

    func downloadEpisode(_ episode: Episode) {
        guard !isDownloading(episode) else { return }

        // isDownloaded is purely local state (Episode isn't CloudKit-mirrored), so this should
        // always match reality - but double-check the bytes are actually present rather than
        // trusting the flag blindly, in case a file was removed by something outside the app.
        if episode.isDownloaded,
           let filename = episode.downloadedFilename,
           FileManager.default.fileExists(atPath: DownloadManager.localFileURL(forStoredFilename: filename).path) {
            return
        }

        guard URL(string: episode.audioURL ?? "") != nil else { return }

        guard downloadTasks.count < maxConcurrentDownloads else {
            pendingDownloadQueue.append(episode)
            activeDownloads[episode.id] = 0.0
            return
        }

        startDownload(episode)
    }

    private func startDownload(_ episode: Episode) {
        guard let url = URL(string: episode.audioURL ?? "") else {
            // Shouldn't happen (validated before queuing), but don't let a bad URL stall the
            // rest of the queue behind it.
            startNextQueuedDownloadIfNeeded()
            return
        }

        let task = urlSession.downloadTask(with: url)
        downloadTasks[episode.id] = task
        activeDownloads[episode.id] = 0.0
        task.resume()
    }

    /// Pulls the next episode off the queue once a download slot frees up. Called after every
    /// completion, failure, and cancellation.
    private func startNextQueuedDownloadIfNeeded() {
        guard downloadTasks.count < maxConcurrentDownloads, !pendingDownloadQueue.isEmpty else { return }
        startDownload(pendingDownloadQueue.removeFirst())
    }

    func cancelDownload(_ episode: Episode) {
        if let task = downloadTasks[episode.id] {
            task.cancel()
            downloadTasks.removeValue(forKey: episode.id)
            activeDownloads.removeValue(forKey: episode.id)
            startNextQueuedDownloadIfNeeded()
            return
        }

        if let index = pendingDownloadQueue.firstIndex(where: { $0.id == episode.id }) {
            pendingDownloadQueue.remove(at: index)
            activeDownloads.removeValue(forKey: episode.id)
        }
    }

    func deleteDownload(_ episode: Episode) {
        guard episode.isDownloaded else { return }
        guard let filename = episode.downloadedFilename else { return }

        try? FileManager.default.removeItem(at: DownloadManager.localFileURL(forStoredFilename: filename))

        episode.isDownloaded = false
        episode.downloadedFilename = nil
        try? modelContext?.save()
    }

    /// Deletes downloaded audio files in the Downloads folder that no live Episode row
    /// references anymore. Every deletion path (retention cleanup, manual "remove download",
    /// unsubscribing) only removes a file if it's still holding a reference to it at the moment
    /// of deletion - so a file can become unreachable disk space if its Episode row is deleted
    /// by any path that isn't holding that exact filename. This is the backstop that reclaims it.
    ///
    /// Only prunes files untouched for at least a day, so this can never race a fresh CloudKit
    /// import (e.g. right after Settings > Reset Local Sync, where the local store is briefly
    /// empty while episodes re-sync) and delete a file that's about to be legitimately re-linked.
    func pruneOrphanedDownloads() {
        guard let modelContext else { return }

        let fileManager = FileManager.default
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: DownloadManager.downloadsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), !fileURLs.isEmpty else { return }

        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.downloadedFilename != nil })
        let referencedFilenames = Set((try? modelContext.fetch(descriptor))?.compactMap { $0.downloadedFilename } ?? [])

        let files = fileURLs.map { url -> (filename: String, modificationDate: Date) in
            let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            return (url.lastPathComponent, modificationDate)
        }
        let orphaned = DownloadPruningPolicy.orphanedDownloadFilenames(files: files, referencedFilenames: referencedFilenames)

        for fileURL in fileURLs where orphaned.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    /// Deletes leftover ".tmp" download files sitting directly in the app's temp directory -
    /// both the OS's raw `CFNetworkDownload_*.tmp` files and our own copies made in
    /// `urlSession(_:downloadTask:didFinishDownloadingTo:)` (named `<uuid>.tmp`, since the copy's
    /// extension is inherited from the system file's, not the audio format). Both are normally
    /// removed within moments of being created; anything still here after an hour was orphaned by
    /// the app dying (crash, force-quit) before it could finish processing or clean up after
    /// itself - that's what filled up `tmp` while `Downloads` stayed empty.
    ///
    /// Only looks at the temp directory's top level and only at ".tmp" files, so it can't touch
    /// unrelated subdirectories other frameworks use (e.g. AVFoundation's media cache).
    func pruneStaleTempDownloads() {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return }

        let files = fileURLs.map { url -> (filename: String, modificationDate: Date, isRegularFile: Bool) in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            return (url.lastPathComponent, values?.contentModificationDate ?? Date(), values?.isRegularFile ?? false)
        }
        let stale = DownloadPruningPolicy.staleTempFilenames(files: files)

        for fileURL in fileURLs where stale.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func saveDownloadedFile(from tempURL: URL, for episodeID: UUID) {
        guard let modelContext = modelContext else {
            print("No model context available")
            return
        }
        
        // Find the episode
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { ep in
                ep.id == episodeID
            }
        )
        
        guard let episode = try? modelContext.fetch(descriptor).first else {
            print("Could not find episode with ID: \(episodeID)")
            return
        }
        
        // Create downloads directory
        do {
            try FileManager.default.createDirectory(at: DownloadManager.downloadsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create downloads directory: \(error)")
            return
        }

        // Generate unique filename. Derive the extension from the episode's audio URL,
        // not tempURL - tempURL's extension comes from URLSession's own internal temp
        // file naming (e.g. "CFNetworkDownload_XXXXXX.tmp"), not the actual audio format.
        let audioURLExtension = URL(string: episode.audioURL ?? "")?.pathExtension ?? ""
        let fileExtension = audioURLExtension.isEmpty ? "mp3" : audioURLExtension
        let fileName = "\(episodeID.uuidString).\(fileExtension)"
        let destinationURL = DownloadManager.localFileURL(forStoredFilename: fileName)
        
        // Move or copy file to final destination
        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Try to move first (faster), fall back to copy if that fails
            do {
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            } catch {
                // If move fails, try copying instead
                try FileManager.default.copyItem(at: tempURL, to: destinationURL)
            }
            
            // Store just the filename, not an absolute path - this device's Downloads folder
            // path is meaningless anywhere else, and isDownloaded/downloadedFilename are local
            // only now anyway (Episode isn't CloudKit-mirrored).
            episode.isDownloaded = true
            episode.downloadedFilename = fileName

            // Add to queue if not already queued - but never resurrect an episode the user
            // already marked played just because its file got (re)downloaded.
            let record = PlaybackRecordStore.recordForMutation(episodeKey: episode.episodeKey, in: modelContext)
            if record.queuePosition == nil && !record.isPlayed {
                // Scoped to queuePosition != nil (the queue itself, always small) rather than
                // fetching every PlaybackRecord ever created (~13,000+ rows and growing).
                let queuedDescriptor = FetchDescriptor<PlaybackRecord>(
                    predicate: #Predicate { $0.queuePosition != nil }
                )
                let queuedRecords = try? modelContext.fetch(queuedDescriptor)
                let maxPosition = queuedRecords?.compactMap { $0.queuePosition }.max() ?? -1
                record.queuePosition = maxPosition + 1
            }

            try modelContext.save()

            print("✅ Successfully saved episode download to: \(destinationURL.path)")
            print("📋 Added episode to queue at position \(record.queuePosition ?? -1)")
            
        } catch {
            print("Failed to save downloaded file: \(error)")
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard downloadTask.originalRequest?.url != nil else { return }
        
        // IMPORTANT: Copy the file immediately before this method returns!
        // The system will delete the temp file after this delegate method completes.
        
        // Create a temporary destination in a location we control
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempDestination = tempDirectory.appendingPathComponent(UUID().uuidString + "." + location.pathExtension)
        
        do {
            // Copy the file immediately to our own temp location
            try FileManager.default.copyItem(at: location, to: tempDestination)
            
            // Now we can safely process the file asynchronously
            Task { @MainActor in
                var episodeID: UUID?
                for (id, task) in downloadTasks {
                    if task == downloadTask {
                        episodeID = id
                        break
                    }
                }
                
                guard let episodeID = episodeID else {
                    // Clean up our temp file if we can't find the episode
                    try? FileManager.default.removeItem(at: tempDestination)
                    return
                }
                
                // Save the file from our temp location
                saveDownloadedFile(from: tempDestination, for: episodeID)
                
                // Clean up our temp file
                try? FileManager.default.removeItem(at: tempDestination)
                
                // Clean up download tracking
                downloadTasks.removeValue(forKey: episodeID)
                activeDownloads.removeValue(forKey: episodeID)
                startNextQueuedDownloadIfNeeded()
            }
        } catch {
            print("Failed to copy temp download file: \(error)")
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        Task { @MainActor in
            // Find the episode ID for this download
            for (id, task) in downloadTasks {
                if task == downloadTask {
                    activeDownloads[id] = progress
                    break
                }
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        
        Task { @MainActor in
            // Find and remove the failed download
            var episodeID: UUID?
            for (id, downloadTask) in downloadTasks {
                if downloadTask == task {
                    episodeID = id
                    break
                }
            }
            
            if let episodeID = episodeID {
                downloadTasks.removeValue(forKey: episodeID)
                activeDownloads.removeValue(forKey: episodeID)
                startNextQueuedDownloadIfNeeded()
            }

            print("Download failed: \(error.localizedDescription)")
        }
    }
}
