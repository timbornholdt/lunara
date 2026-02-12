import Foundation
import Network

final class WiFiReachabilityMonitor: WiFiReachabilityMonitoring {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var onChange: (@Sendable (Bool) -> Void)?

    private(set) var isOnWiFi = false

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(label: "Lunara.WiFiReachabilityMonitor")
    ) {
        self.monitor = monitor
        self.queue = queue
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connectedOnWiFi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            self.lock.lock()
            self.isOnWiFi = connectedOnWiFi
            let handler = self.onChange
            self.lock.unlock()
            handler?(connectedOnWiFi)
        }
    }

    func start() {
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    func setOnWiFiChangeHandler(_ handler: (@Sendable (Bool) -> Void)?) {
        lock.lock()
        onChange = handler
        lock.unlock()
    }
}
