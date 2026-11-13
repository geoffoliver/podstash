//
//  LaunchHousekeepingTests.swift
//  PodstashTests
//

import Testing
@testable import Podstash

@Suite("LaunchHousekeeping")
struct LaunchHousekeepingTests {

    @Test("The first call runs the work")
    func firstCallRuns() {
        let housekeeping = LaunchHousekeeping()
        var runs = 0

        housekeeping.runOnce { runs += 1 }

        #expect(runs == 1)
    }

    // The macOS main window's root view (and so its .onAppear) is rebuilt every time the window
    // is closed and reopened - launch-only work must not repeat each time.
    @Test("Later calls don't run the work again")
    func laterCallsSkipped() {
        let housekeeping = LaunchHousekeeping()
        var runs = 0

        housekeeping.runOnce { runs += 1 }
        housekeeping.runOnce { runs += 1 }
        housekeeping.runOnce { runs += 1 }

        #expect(runs == 1)
    }
}
