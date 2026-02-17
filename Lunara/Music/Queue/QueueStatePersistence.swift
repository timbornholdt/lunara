import Foundation

protocol QueueStatePersisting {
    func load() throws -> QueueSnapshot?
    func save(_ snapshot: QueueSnapshot) throws
    func clear() throws
}

struct FileQueueStatePersistence: QueueStatePersisting {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func load() throws -> QueueSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(QueueSnapshot.self, from: data)
    }

    func save(_ snapshot: QueueSnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupportURL
            .appendingPathComponent("Lunara", isDirectory: true)
            .appendingPathComponent("queue_state.json", isDirectory: false)
    }
}
