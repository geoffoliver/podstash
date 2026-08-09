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

        // `isDownloaded` reflects whether *any* device has the file, since it syncs via
        // iCloud. Only skip the download if the bytes are actually present on this device.
        if episode.isDownloaded,
           let filename = episode.downloadedFilename,
           FileManager.default.fileExists(atPath: DownloadManager.localFileURL(forStoredFilename: filename).path) {
            return
        }

        guard let url = URL(string: episode.audioURL) else { return }

        let task = urlSession.downloadTask(with: url)
        downloadTasks[episode.id] = task
        activeDownloads[episode.id] = 0.0
        task.resume()
    }

    func cancelDownload(_ episode: Episode) {
        guard let task = downloadTasks[episode.id] else { return }
        task.cancel()
        downloadTasks.removeValue(forKey: episode.id)
        activeDownloads.removeValue(forKey: episode.id)
    }

    func deleteDownload(_ episode: Episode) {
        guard episode.isDownloaded else { return }
        guard let filename = episode.downloadedFilename else { return }

        try? FileManager.default.removeItem(at: DownloadManager.localFileURL(forStoredFilename: filename))

        episode.isDownloaded = false
        episode.downloadedFilename = nil
        try? modelContext?.save()
    }

    /// Finds episodes marked downloaded via iCloud sync from another device whose file isn't
    /// actually present here yet, and starts downloading them locally - so "downloaded"
    /// follows you across devices instead of silently falling back to streaming.
    func syncFollowMeDownloads(settings: AppSettings) {
        guard settings.iCloudSyncEnabled else { return }
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { $0.isDownloaded }
        )
        guard let episodes = try? modelContext.fetch(descriptor) else { return }

        for episode in episodes {
            downloadEpisode(episode)
        }
    }
    
    /// Deletes downloaded audio files in the Downloads folder that no live Episode row
    /// references anymore. Every deletion path (retention cleanup, manual "remove download",
    /// unsubscribing) only removes a file if it's still holding a reference to it at the moment
    /// of deletion - so a file downloaded under one duplicate Episode row (see
    /// EpisodeCleanupManager.deduplicateEpisodes) becomes permanently unreachable disk space the
    /// instant that specific row is superseded, merged away, or deleted by any path that isn't
    /// holding that exact filename. This is the backstop that reclaims it.
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

        let cutoff = Date().addingTimeInterval(-60 * 60 * 24)

        for fileURL in fileURLs where !referencedFilenames.contains(fileURL.lastPathComponent) {
            let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            guard modificationDate < cutoff else { continue }
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
        // The filename is deterministic (episode id + extension) so every device that
        // downloads this episode independently lands on the same name.
        let audioURLExtension = URL(string: episode.audioURL)?.pathExtension ?? ""
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
            
            // Update episode - store just the filename, not an absolute path, since this
            // syncs via iCloud and only the filename is meaningful on another device.
            episode.isDownloaded = true
            episode.downloadedFilename = fileName
            
            // Add to queue if not already in queue - but never resurrect an episode the user
            // already marked played just because its file got redownloaded (e.g. via
            // syncFollowMeDownloads after the local copy went missing).
            if episode.queuePosition == nil && !episode.isPlayed {
                // Find the highest queue position
                let allEpisodesDescriptor = FetchDescriptor<Episode>()
                let allEpisodes = try? modelContext.fetch(allEpisodesDescriptor)
                let maxPosition = allEpisodes?.compactMap { $0.queuePosition }.max() ?? -1
                episode.queuePosition = maxPosition + 1
            }
            
            try modelContext.save()
            
            print("✅ Successfully saved episode download to: \(destinationURL.path)")
            print("📋 Added episode to queue at position \(episode.queuePosition ?? -1)")
            
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
            }
            
            print("Download failed: \(error.localizedDescription)")
        }
    }
}
