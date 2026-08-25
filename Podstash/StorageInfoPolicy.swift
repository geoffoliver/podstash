//
//  StorageInfoPolicy.swift
//  Podstash
//

import Foundation

/// Pure math behind Settings' Storage row, pulled out so it's testable without touching disk.
/// Sizes are summed from each downloaded episode's *actual* file size on disk - not estimated
/// from duration (the old approach), which silently read "0 MB" for any episode downloaded but
/// never played (duration unmeasured) and was badly wrong for video besides, since a video
/// enclosure runs far more than the audio-tuned "1 MB per minute" the estimate assumed.
enum StorageInfoPolicy {
    static func totalBytes(downloadedFileSizes: [Int64]) -> Int64 {
        downloadedFileSizes.reduce(0, +)
    }

    /// MB for anything under a gigabyte, one decimal place of GB above that.
    static func formattedSize(bytes: Int64) -> String {
        let megabytes = Double(bytes) / (1024.0 * 1024.0)
        if megabytes >= 1024 {
            return String(format: "%.1f GB", megabytes / 1024.0)
        }
        return "\(Int(megabytes)) MB"
    }
}
