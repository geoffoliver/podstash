//
//  PlaybackTimeDisplayPolicy.swift
//  Podstash
//

import Foundation

/// Formatting for the elapsed-time label under the playback scrubber. Tapping the label toggles
/// it between showing elapsed time and time remaining (as "-h:mm:ss"); the duration label on the
/// other side of the scrubber is unaffected.
enum PlaybackTimeDisplayPolicy {
    static func format(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    static func elapsedLabel(currentTime: TimeInterval, duration: TimeInterval, showingRemaining: Bool) -> String {
        guard showingRemaining else { return format(currentTime) }
        return "-" + format(max(duration - currentTime, 0))
    }
}
