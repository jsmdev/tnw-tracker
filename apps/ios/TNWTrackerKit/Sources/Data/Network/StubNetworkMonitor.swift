#if DEBUG
    import Foundation

    /// Test/preview double for `NetworkMonitoring`.
    /// Lets tests force `isOnline` deterministically without touching the real path monitor.
    @MainActor
    public final class StubNetworkMonitor: NetworkMonitoring {
        public var isOnline: Bool
        public var onReconnect: (@MainActor () -> Void)?

        public init(isOnline: Bool = true) {
            self.isOnline = isOnline
        }
    }
#endif
