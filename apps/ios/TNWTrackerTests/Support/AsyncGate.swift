import Foundation

/// Holds whoever waits on it until it is opened: lets a test stop a fake
/// server call half way and look at the app meanwhile, without sleeping.
actor AsyncGate {
    private(set) var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var cancellable: [UUID: CheckedContinuation<Void, Never>] = [:]

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Like `wait()`, but a cancelled waiter goes on at once, as a network
    /// request in flight ends when its task is cancelled.
    func waitUnlessCancelled() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isOpen || Task.isCancelled {
                    continuation.resume()
                } else {
                    cancellable[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.resume(id) }
        }
    }

    func open() {
        isOpen = true
        for waiter in waiters + cancellable.values {
            waiter.resume()
        }
        waiters = []
        cancellable = [:]
    }

    private func resume(_ id: UUID) {
        cancellable.removeValue(forKey: id)?.resume()
    }
}
