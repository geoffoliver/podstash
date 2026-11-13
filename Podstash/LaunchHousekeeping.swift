//
//  LaunchHousekeeping.swift
//  Podstash
//

import Foundation

/// Runs launch-only work exactly once per process. The main window's root view is where launch
/// setup lives (it needs the view tree's environment), but on macOS that view - and its
/// .onAppear - is rebuilt every time the window is closed and reopened. Without this gate, every
/// reopen re-ran the full-table PlaybackRecord dedup and download pruning on the main thread
/// before the window could finish appearing.
final class LaunchHousekeeping {
    static let shared = LaunchHousekeeping()

    private var hasRun = false

    func runOnce(_ work: () -> Void) {
        guard !hasRun else { return }
        hasRun = true
        work()
    }
}
