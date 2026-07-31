//
//  PlaybackState.swift
//  Podstash
//
//  Created by Geoff Oliver on 7/30/26.
//

import Foundation
import Combine

/// Separate observable object for frequently-updating playback state
/// This prevents the entire app from re-rendering every 0.5 seconds
@MainActor
class PlaybackState: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying: Bool = false
}
