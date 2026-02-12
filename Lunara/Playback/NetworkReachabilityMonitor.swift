import Foundation
import Network

final class NetworkReachabilityMonitor: NetworkReachabilityMonitoring {
    static let shared = NetworkReachabilityMonitor()

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var reachable = true

    var isReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachable
    }

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(label: "Lunara.NetworkReachabilityMonitor")
    ) {
        self.monitor = monitor
        self.queue = queue
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.reachable = path.status == .satisfied
            self.lock.unlock()
        }
        self.monitor.start(queue: queue)
    }
}
