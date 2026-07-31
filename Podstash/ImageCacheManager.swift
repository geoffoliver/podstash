//
//  ImageCacheManager.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import SwiftUI
import SwiftData
import AppKit
import Combine

@MainActor
final class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    
    @Published private(set) var cachingProgress: [String: Double] = [:] // URL -> Progress
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var activeTasks: [String: Task<URL?, Never>] = [:]
    
    // In-memory cache for quick access
    private var memoryCache: [String: NSImage] = [:]
    private let maxMemoryCacheSize = 50 // Maximum number of images to keep in memory
    
    init() {
        // Create cache directory in Caches folder (can be cleared by system)
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cachesDirectory.appendingPathComponent("ArtworkCache", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public Methods
    
    /// Get cached image synchronously if available
    func getCachedImage(for urlString: String) -> NSImage? {
        // Check memory cache first
        if let image = memoryCache[urlString] {
            return image
        }
        
        // Check disk cache
        if let fileURL = diskCacheURL(for: urlString),
           fileManager.fileExists(atPath: fileURL.path),
           let image = NSImage(contentsOf: fileURL) {
            // Add to memory cache
            addToMemoryCache(image, for: urlString)
            return image
        }
        
        return nil
    }
    
    /// Download and cache image asynchronously
    func cacheImage(from urlString: String) async -> URL? {
        // Check if already cached on disk
        if let cachedURL = diskCacheURL(for: urlString),
           fileManager.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        
        // Check if already downloading
        if let existingTask = activeTasks[urlString] {
            return await existingTask.value
        }
        
        // Start new download task
        let task = Task<URL?, Never> { @MainActor in
            await downloadAndCache(urlString: urlString)
        }
        
        activeTasks[urlString] = task
        let result = await task.value
        activeTasks.removeValue(forKey: urlString)
        
        return result
    }
    
    /// Cache all artwork for a podcast (including its episodes)
    func cacheArtwork(for podcast: Podcast) async {
        var urls: [String] = []
        
        // Add podcast artwork
        if let artworkURL = podcast.artworkURL {
            urls.append(artworkURL)
        }
        
        // Add episode artwork (unique URLs only)
        for episode in podcast.episodes {
            if let artworkURL = episode.artworkURL, !urls.contains(artworkURL) {
                urls.append(artworkURL)
            }
        }
        
        // Download all artwork concurrently
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { @MainActor in
                    _ = await self.cacheImage(from: url)
                }
            }
        }
    }
    
    /// Clear all cached artwork
    func clearCache() {
        memoryCache.removeAll()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Clear only memory cache (disk cache remains)
    func clearMemoryCache() {
        memoryCache.removeAll()
    }
    
    /// Get the size of the disk cache in bytes
    func getCacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    // MARK: - Private Methods
    
    private func downloadAndCache(urlString: String) async -> URL? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        do {
            cachingProgress[urlString] = 0.0
            
            let (data, _) = try await URLSession.shared.data(from: url)
            
            cachingProgress[urlString] = 0.5
            
            // Verify it's a valid image
            guard let image = NSImage(data: data) else {
                cachingProgress.removeValue(forKey: urlString)
                return nil
            }
            
            // Save to disk cache
            guard let cachedURL = diskCacheURL(for: urlString) else {
                cachingProgress.removeValue(forKey: urlString)
                return nil
            }
            
            try data.write(to: cachedURL)
            
            // Add to memory cache
            addToMemoryCache(image, for: urlString)
            
            cachingProgress[urlString] = 1.0
            
            // Remove progress after a short delay
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                cachingProgress.removeValue(forKey: urlString)
            }
            
            return cachedURL
            
        } catch {
            print("Failed to cache image from \(urlString): \(error)")
            cachingProgress.removeValue(forKey: urlString)
            return nil
        }
    }
    
    private func diskCacheURL(for urlString: String) -> URL? {
        // Create a safe filename from the URL
        let hash = urlString.hash
        let filename = "\(abs(hash)).jpg"
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    private func addToMemoryCache(_ image: NSImage, for urlString: String) {
        // Simple LRU-style: if cache is full, remove oldest entries
        if memoryCache.count >= maxMemoryCacheSize {
            // Remove first entry (oldest in iteration order)
            if let firstKey = memoryCache.keys.first {
                memoryCache.removeValue(forKey: firstKey)
            }
        }
        
        memoryCache[urlString] = image
    }
}

// MARK: - Helper Extension

extension Image {
    init?(nsImage: NSImage?) {
        guard let nsImage = nsImage else {
            return nil
        }
        self.init(nsImage: nsImage)
    }
}
