//
//  SparkleUpdater.swift
//  Podstash
//
//  Created by Geoff Oliver on 8/2/26.
//

#if os(macOS)
import SwiftUI
import Combine
import Sparkle

@MainActor
final class SparkleUpdaterViewModel: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
