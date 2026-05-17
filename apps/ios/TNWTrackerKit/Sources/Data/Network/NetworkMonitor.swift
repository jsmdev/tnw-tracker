import Foundation
import Network
import Observation
import os.log

private let logger = Logger(subsystem: "com.tnwtracker", category: "network")

/// Abstraction over connectivity status — allows mocking in tests
/// without spinning up a real `NWPathMonitor`.
@MainActor
public protocol NetworkMonitoring: AnyObject {
    var isOnline: Bool { get }
}

/// Production implementation backed by `NWPathMonitor`.
/// Reactive `@Observable` so SwiftUI views can react to connectivity changes.
@MainActor
@Observable
public final class NetworkMonitor: NetworkMonitoring {
    public private(set) var isOnline: Bool = true

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    public init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "com.tnwtracker.network-monitor")

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isOnline != online {
                    logger.info("NetworkMonitor: isOnline → \(online, privacy: .public)")
                }
                isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
