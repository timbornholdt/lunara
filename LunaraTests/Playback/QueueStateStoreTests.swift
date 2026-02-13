import Foundation
import Testing
@testable import Lunara

struct QueueStateStoreTests {
    @Test func saveLoadRoundTrip() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-state-store-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "QueueStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = QueueStateStore(baseURL: tempRoot, fileManager: .default, defaults: defaults)
        let state = QueueState(
            entries: [
                QueueEntry(
                    id: UUID(),
                    track: PlexTrack(
                        ratingKey: "t1",
                        title: "One",
                        index: 1,
                        parentIndex: nil,
                        parentRatingKey: "a1",
                        duration: 1000,
                        media: nil
                    ),
                    album: nil,
                    albumRatingKeys: [],
                    artworkRequest: nil,
                    isPlayable: true,
                    skipReason: nil
                )
            ],
            currentIndex: 0,
            elapsedTime: 12.5,
            isPlaying: false
        )

        try store.save(state)
        let loaded = try store.load()

        #expect(loaded == state)
    }

    @Test func loadsFromDefaultsWhenFileMissing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-state-store-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "QueueStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = QueueStateStore(baseURL: tempRoot, fileManager: .default, defaults: defaults)
        let state = QueueState(
            entries: [],
            currentIndex: nil,
            elapsedTime: 0,
            isPlaying: false
        )
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: QueueStateStore.defaultsKey)

        let loaded = try store.load()
        #expect(loaded == state)
    }
}
