import Foundation
import os

actor ScrobbleQueue {

    private var entries: [ScrobbleEntry] = []
    private let fileURL: URL
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "ScrobbleQueue")

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Lunara", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pending_scrobbles.json")
        loadFromDisk()
    }

    var pendingCount: Int { entries.count }
    var pendingEntries: [ScrobbleEntry] { entries }

    func enqueue(_ entry: ScrobbleEntry) {
        entries.append(entry)
        saveToDisk()
    }

    /// Returns up to `limit` entries for batch submission.
    func dequeue(limit: Int = 50) -> [ScrobbleEntry] {
        Array(entries.prefix(limit))
    }

    /// Removes the first `count` entries after successful submission.
    func removeFront(_ count: Int) {
        entries.removeFirst(min(count, entries.count))
        saveToDisk()
    }

    func removeAll() {
        entries.removeAll()
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([ScrobbleEntry].self, from: data)
            logger.info("Loaded \(self.entries.count) pending scrobbles from disk")
        } catch {
            logger.error("Failed to load scrobble queue: \(error.localizedDescription, privacy: .public)")
            entries = []
        }
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save scrobble queue: \(error.localizedDescription, privacy: .public)")
        }
    }
}
