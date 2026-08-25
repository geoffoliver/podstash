//
//  NetworkMonitor.swift
//  Podstash
//

import Foundation
import Network

/// Thin wrapper around NWPathMonitor exposing current Wi-Fi status. Kept separate from the
/// actual gating decision (VideoDownloadPolicy) so that logic stays pure and testable without a
/// real network path. Defaults to `true` until the first path update arrives, matching
/// refreshOnlyOnWiFi's existing "don't block on an unknown state" behavior.
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "me.geoffoliver.Podstash.NetworkMonitor")

    private(set) var isOnWiFi = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnWiFi = path.usesInterfaceType(.wifi)
            Task { @MainActor in
                self?.isOnWiFi = isOnWiFi
            }
        }
        monitor.start(queue: queue)
    }
}
