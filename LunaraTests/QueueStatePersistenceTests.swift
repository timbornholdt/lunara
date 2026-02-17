import Foundation
import Testing
@testable import Lunara

@MainActor
struct QueueStatePersistenceTests {
    @Test
    func saveThenLoad_roundTripsQueueSnapshot() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("queue_state.json")
        let persistence = FileQueueStatePersistence(fileURL: fileURL)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let snapshot = QueueSnapshot(
            items: [
                QueueItem(trackID: "track-1", url: URL(string: "https://example.com/1.mp3")!),
                QueueItem(trackID: "track-2", url: URL(string: "https://example.com/2.mp3")!)
            ],
            currentIndex: 1,
            elapsed: 31
        )

        try persistence.save(snapshot)
        let loaded = try persistence.load()

        #expect(loaded == snapshot)
    }

    @Test
    func clear_removesPersistedSnapshot() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("queue_state.json")
        let persistence = FileQueueStatePersistence(fileURL: fileURL)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let snapshot = QueueSnapshot(
            items: [QueueItem(trackID: "track-1", url: URL(string: "https://example.com/1.mp3")!)],
            currentIndex: 0,
            elapsed: 0
        )

        try persistence.save(snapshot)
        try persistence.clear()

        let loaded = try persistence.load()
        #expect(loaded == nil)
    }
}
