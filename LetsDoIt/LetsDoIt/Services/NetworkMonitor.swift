import Foundation
import Network
import Observation

/// NWPathMonitor wrapper that publishes connectivity state.
/// Singleton pattern — use `NetworkMonitor.shared` throughout the app.
@Observable final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Whether the device currently has an active network connection.
    @MainActor var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
