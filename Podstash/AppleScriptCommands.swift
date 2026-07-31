//
//  AppleScriptCommands.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/31/26.
//

#if os(macOS)
import Foundation
import AppKit

/// AppleScript command for play/pause toggle
/// Used by Airfoil for remote control
@objc(PlayPauseCommand)
class PlayPauseCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuCoordinator.shared.audioPlayer?.togglePlayPause()
        }
        return nil
    }
}

/// AppleScript command to skip forward in current episode
/// Used by Airfoil for remote control
/// Skips forward by the configured interval (default 30 seconds)
@objc(NextCommand)
class NextCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuCoordinator.shared.audioPlayer?.skipForward()
        }
        return nil
    }
}

/// AppleScript command to skip backward in current episode
/// Used by Airfoil for remote control
/// Skips backward by the configured interval (default 15 seconds)
@objc(PreviousCommand)
class PreviousCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuCoordinator.shared.audioPlayer?.skipBackward()
        }
        return nil
    }
}
#endif
