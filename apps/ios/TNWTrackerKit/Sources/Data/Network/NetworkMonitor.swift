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
    /// Called when the connection comes back (offline → online), so the sync
    /// sends what was saved meanwhile (S3).
    var onReconnect: (@MainActor () -> Void)? { get set }
}

/// Production implementation backed by `NWPathMonitor`.
/// Reactive `@Observable` so SwiftUI views can react to connectivity changes.
@MainActor
@Observable
public final class NetworkMonitor: NetworkMonitoring {
    public private(set) var isOnline: Bool = true
    @ObservationIgnored public var onReconnect: (@MainActor () -> Void)?

    private let monitor: NWPathMonitor?

    public convenience init() {
        self.init(monitorsPath: true)
    }

    /// Without `monitorsPath`, only `apply(online:)` changes the status (tests).
    init(monitorsPath: Bool) {
        guard monitorsPath else {
            monitor = nil
            return
        }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.apply(online: online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.tnwtracker.network-monitor"))
    }

    /// Records a path update; going from offline to online calls `onReconnect`.
    func apply(online: Bool) {
        guard isOnline != online else { return }
        logger.info("NetworkMonitor: isOnline → \(online, privacy: .public)")
        isOnline = online
        if online { onReconnect?() }
    }

    deinit {
        monitor?.cancel()
    }
}
