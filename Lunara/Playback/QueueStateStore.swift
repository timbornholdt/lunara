import Foundation

final class QueueStateStore: QueueStateStoring {
    static let defaultsKey = "queue.state.data"

    private let baseURL: URL
    private let fileManager: FileManager
    private let stateURL: URL
    private let defaults: UserDefaults

    init(baseURL: URL? = nil, fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        let resolvedBase: URL
        if let baseURL {
            resolvedBase = baseURL
        } else {
            resolvedBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Lunara", isDirectory: true)
        }
        self.baseURL = resolvedBase
        self.fileManager = fileManager
        self.defaults = defaults
        self.stateURL = resolvedBase.appendingPathComponent("queue-state.json")
    }

    func load() throws -> QueueState? {
        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(QueueState.self, from: data) {
            return state
        }
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            return nil
        }
        return try JSONDecoder().decode(QueueState.self, from: data)
    }

    func save(_ state: QueueState) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: stateURL.path) {
            try fileManager.removeItem(at: stateURL)
        }
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
