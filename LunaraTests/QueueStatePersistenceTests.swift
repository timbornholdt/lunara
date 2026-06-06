import Foundation
import Testing
@testable import Lunara

@MainActor
struct QueueStatePersistenceTests {
    @Test
    func saveThenLoad_roundTripsQueueSnapshot() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("queue_state.json")
        let persistence = FileQueueStatePersistence(fileURL: fileURL)
        defer {
            do {
                try FileManager.default.removeItem(at: directoryURL)
            } catch {
                // Safe to ignore cleanup failures for temp test directories.
            }
        }

        let snapshot = QueueSnapshot(
            items: [
                QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1"),
                QueueItem(trackID: "track-2", streamKey: "/library/metadata/track-2")
            ],
            currentIndex: 1,
            elapsed: 31
        )

        try await persistence.save(snapshot)
        let loaded = try persistence.load()

        #expect(loaded == snapshot)
        // Persisted snapshot carries stable identifiers only — no resolved URLs.
        #expect(loaded?.items.first?.streamKey == "/library/metadata/track-1")
    }

    @Test
    func clear_removesPersistedSnapshot() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("queue_state.json")
        let persistence = FileQueueStatePersistence(fileURL: fileURL)
        defer {
            do {
                try FileManager.default.removeItem(at: directoryURL)
            } catch {
                // Safe to ignore cleanup failures for temp test directories.
            }
        }

        let snapshot = QueueSnapshot(
            items: [QueueItem(trackID: "track-1", streamKey: "/library/metadata/track-1")],
            currentIndex: 0,
            elapsed: 0
        )

        try await persistence.save(snapshot)
        try await persistence.clear()

        let loaded = try persistence.load()
        #expect(loaded == nil)
    }
}
