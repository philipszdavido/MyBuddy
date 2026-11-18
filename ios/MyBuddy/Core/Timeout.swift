//
//  Timeout.swift
//

import Foundation

/// Runs `operation`, but returns after `seconds` even if it is still running. Needed for best-effort
/// cleanup (e.g. unregistering a push token on logout) over non-cancellable backend calls that would
/// otherwise hang while offline. The operation keeps running in the background after a timeout.
func withTimeout(seconds: Double, _ operation: @escaping @Sendable () async -> Void) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let gate = OnceGate(continuation)
        Task { await operation(); gate.fire() }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            gate.fire()
        }
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
    func fire() {
        let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let current = continuation
            continuation = nil
            return current
        }
        c?.resume()
    }
}
