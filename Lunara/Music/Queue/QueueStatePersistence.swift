import Foundation

protocol QueueStatePersisting: AnyObject {
    func load() throws -> QueueSnapshot?
    func save(_ snapshot: QueueSnapshot) async throws
    func clear() async throws
}

final class FileQueueStatePersistence: QueueStatePersisting {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let ioQueue = DispatchQueue(label: "holdings.chinlock.lunara.queue.persistence")

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
        try ioQueue.sync {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(QueueSnapshot.self, from: data)
        }
    }

    func save(_ snapshot: QueueSnapshot) async throws {
        let encodedData = try await MainActor.run {
            try self.encoder.encode(snapshot)
        }
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let directoryURL = self.fileURL.deletingLastPathComponent()
                    if !self.fileManager.fileExists(atPath: directoryURL.path) {
                        try self.fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                    }

                    try encodedData.write(to: self.fileURL, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func clear() async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    guard self.fileManager.fileExists(atPath: self.fileURL.path) else {
                        continuation.resume()
                        return
                    }

                    try self.fileManager.removeItem(at: self.fileURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupportURL
            .appendingPathComponent("Lunara", isDirectory: true)
            .appendingPathComponent("queue_state.json", isDirectory: false)
    }
}
