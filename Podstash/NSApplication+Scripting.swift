//
//  NSApplication+Scripting.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/31/26.
//

#if os(macOS)
import Foundation
import AppKit

/// Extension to provide AppleScript properties for Airfoil integration
/// These properties are accessed via the scripting bridge when Airfoil
/// queries for track metadata to display in Airfoil Speakers
extension NSApplication {
    
    // MARK: - AppleScript Properties
    // These need to be @objc methods that return the values
    
    @objc func trackTitle() -> String? {
        return MenuCoordinator.shared.audioPlayer?.currentEpisode?.title
    }
    
    @objc func artist() -> String? {
        return MenuCoordinator.shared.audioPlayer?.currentPodcast?.title
    }

    @objc func album() -> String? {
        return MenuCoordinator.shared.audioPlayer?.currentPodcast?.title
    }
    
    @objc func duration() -> NSNumber? {
        guard let duration = MenuCoordinator.shared.audioPlayer?.progress.duration,
              !duration.isNaN && !duration.isInfinite else {
            return nil
        }
        return NSNumber(value: Int(duration))
    }
    
    @objc func logo() -> NSAppleEventDescriptor? {
        guard let artworkURL = MenuCoordinator.shared.audioPlayer?.currentPodcast?.artworkURL else {
            return nil
        }
        
        // Try to get cached image first (fast!)
        var tiffData: Data?
        
        if let cachedImage = ImageCacheManager.shared.getCachedImage(for: artworkURL) {
            tiffData = cachedImage.tiffRepresentation
        } else if let url = URL(string: artworkURL) {
            // If not cached, try to fetch synchronously
            do {
                let imageData = try Data(contentsOf: url)
                if let image = NSImage(data: imageData) {
                    tiffData = image.tiffRepresentation
                }
            } catch {
                // If network fetch fails, return nil (missing value)
                return nil
            }
        }
        
        // Convert to AppleEvent descriptor with proper type
        guard let data = tiffData else {
            return nil
        }
        
        // Use 'TIFF' FourCharCode for TIFF picture type
        let tiffType: OSType = 0x54494646 // 'TIFF' in hex
        return NSAppleEventDescriptor(descriptorType: tiffType, data: data)
    }
    
    // MARK: - AppleScript Commands
    
    @objc func handlePlayPauseScriptCommand(_ command: NSScriptCommand) -> Any? {
        // Execute on main thread synchronously
        if Thread.isMainThread {
            MenuCoordinator.shared.audioPlayer?.togglePlayPause()
        } else {
            DispatchQueue.main.sync {
                MenuCoordinator.shared.audioPlayer?.togglePlayPause()
            }
        }
        return nil
    }
    
    @objc func handleNextScriptCommand(_ command: NSScriptCommand) -> Any? {
        // Execute on main thread synchronously
        if Thread.isMainThread {
            MenuCoordinator.shared.audioPlayer?.skipForward()
        } else {
            DispatchQueue.main.sync {
                MenuCoordinator.shared.audioPlayer?.skipForward()
            }
        }
        return nil
    }
    
    @objc func handlePreviousScriptCommand(_ command: NSScriptCommand) -> Any? {
        // Execute on main thread synchronously
        if Thread.isMainThread {
            MenuCoordinator.shared.audioPlayer?.skipBackward()
        } else {
            DispatchQueue.main.sync {
                MenuCoordinator.shared.audioPlayer?.skipBackward()
            }
        }
        return nil
    }
}
#endif
