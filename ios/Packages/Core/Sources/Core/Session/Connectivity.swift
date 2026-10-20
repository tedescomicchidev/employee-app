import Foundation
import Network

/// Whether the device has a network path. AGENT chats need a connection (NFR-007): the composer is
/// disabled while offline instead of letting a turn fail.
public protocol Connectivity: Sendable {
    /// Emits the current state first, then every change. `true` means online.
    func updates() -> AsyncStream<Bool>
}

public struct PathConnectivity: Connectivity {
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            monitor.start(queue: DispatchQueue(label: "connectivity"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }
}

/// Fixed answer for tests, screenshots and UI tests.
public struct StaticConnectivity: Connectivity {
    public let online: Bool

    public init(online: Bool) { self.online = online }

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(online)
            // Stays open like the real monitor; the consumer's task cancellation ends it.
        }
    }
}
