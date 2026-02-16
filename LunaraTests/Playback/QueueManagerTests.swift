import Foundation
import Testing
@testable import Lunara

@MainActor
struct QueueManagerTests {
    @Test func playNowReplacesQueueAndStartsAtFirstTrack() async {
        let store = InMemoryQueueStateStore()
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }
        let entries = [
            makeEntry(trackKey: "t1", title: "One"),
            makeEntry(trackKey: "t2", title: "Two")
        ]

        let result = await queueManager.insert(
            QueueInsertRequest(
                mode: .playNow,
                entries: entries,
                signature: "album:a",
                requestedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(result.duplicateBlocked == false)
        #expect(result.insertedCount == 2)
        #expect(result.state.currentIndex == 0)
        #expect(result.state.isPlaying == true)
        #expect(result.state.elapsedTime == 0)
        #expect(result.state.entries.map(\.track.ratingKey) == ["t1", "t2"])
    }

    @Test func playNextInsertsImmediatelyAfterCurrentTrack() async {
        let store = InMemoryQueueStateStore(
            initial: QueueState(
                entries: [
                    makeEntry(trackKey: "a1", title: "A1"),
                    makeEntry(trackKey: "a2", title: "A2")
                ],
                currentIndex: 0,
                elapsedTime: 12,
                isPlaying: true
            )
        )
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }
        let nextEntries = [
            makeEntry(trackKey: "b1", title: "B1"),
            makeEntry(trackKey: "b2", title: "B2")
        ]

        let result = await queueManager.insert(
            QueueInsertRequest(
                mode: .playNext,
                entries: nextEntries,
                signature: "album:b",
                requestedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(result.state.entries.map(\.track.ratingKey) == ["a1", "b1", "b2", "a2"])
        #expect(result.state.currentIndex == 0)
    }

    @Test func playLaterAppendsToTail() async {
        let store = InMemoryQueueStateStore(
            initial: QueueState(
                entries: [
                    makeEntry(trackKey: "a1", title: "A1"),
                    makeEntry(trackKey: "a2", title: "A2")
                ],
                currentIndex: 1,
                elapsedTime: 5,
                isPlaying: false
            )
        )
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }

        let result = await queueManager.insert(
            QueueInsertRequest(
                mode: .playLater,
                entries: [makeEntry(trackKey: "z1", title: "Z1")],
                signature: "track:z1",
                requestedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(result.state.entries.map(\.track.ratingKey) == ["a1", "a2", "z1"])
        #expect(result.state.currentIndex == 1)
    }

    @Test func emptyQueuePlayLaterBehavesLikePlayNow() async {
        let store = InMemoryQueueStateStore()
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }

        let result = await queueManager.insert(
            QueueInsertRequest(
                mode: .playLater,
                entries: [makeEntry(trackKey: "x1", title: "X1")],
                signature: "track:x1",
                requestedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(result.state.currentIndex == 0)
        #expect(result.state.isPlaying == true)
        #expect(result.state.entries.map(\.track.ratingKey) == ["x1"])
    }

    @Test func clearUpcomingKeepsCurrentTrackOnly() async {
        let current = makeEntry(trackKey: "a1", title: "A1")
        let store = InMemoryQueueStateStore(
            initial: QueueState(
                entries: [
                    makeEntry(trackKey: "x0", title: "X0"),
                    current,
                    makeEntry(trackKey: "a2", title: "A2"),
                    makeEntry(trackKey: "a3", title: "A3")
                ],
                currentIndex: 1,
                elapsedTime: 44,
                isPlaying: true
            )
        )
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }

        let state = await queueManager.clearUpcoming()

        #expect(state.entries.count == 2)
        #expect(state.entries.map(\.track.ratingKey) == ["x0", "a1"])
        #expect(state.currentIndex == 1)
    }

    @Test func removeUpcomingRemovesSelectedEntry() async {
        let keep = makeEntry(trackKey: "k1", title: "Keep")
        let remove = makeEntry(trackKey: "r1", title: "Remove")
        let store = InMemoryQueueStateStore(
            initial: QueueState(
                entries: [
                    makeEntry(trackKey: "c1", title: "Current"),
                    remove,
                    keep
                ],
                currentIndex: 0,
                elapsedTime: 0,
                isPlaying: true
            )
        )
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }

        let state = await queueManager.removeUpcoming(entryID: remove.id)

        #expect(state.entries.map(\.track.ratingKey) == ["c1", "k1"])
        #expect(state.currentIndex == 0)
    }

    @Test func duplicateBurstBlocksIdenticalInsertWithinOneSecond() async {
        let store = InMemoryQueueStateStore()
        var now = Date(timeIntervalSince1970: 100)
        let queueManager = QueueManager(store: store) { now }
        let request = QueueInsertRequest(
            mode: .playNow,
            entries: [makeEntry(trackKey: "a1", title: "A1")],
            signature: "album:a",
            requestedAt: now
        )

        let first = await queueManager.insert(request)
        now = Date(timeIntervalSince1970: 100.5)
        let second = await queueManager.insert(
            QueueInsertRequest(mode: .playNow, entries: request.entries, signature: "album:a", requestedAt: now)
        )

        #expect(first.duplicateBlocked == false)
        #expect(second.duplicateBlocked == true)
    }

    @Test func duplicateAllowedAfterOneSecondWindow() async {
        let store = InMemoryQueueStateStore()
        var now = Date(timeIntervalSince1970: 100)
        let queueManager = QueueManager(store: store) { now }
        let request = QueueInsertRequest(
            mode: .playNow,
            entries: [makeEntry(trackKey: "a1", title: "A1")],
            signature: "album:a",
            requestedAt: now
        )

        _ = await queueManager.insert(request)
        now = Date(timeIntervalSince1970: 101.1)
        let second = await queueManager.insert(
            QueueInsertRequest(mode: .playNow, entries: request.entries, signature: "album:a", requestedAt: now)
        )

        #expect(second.duplicateBlocked == false)
        #expect(second.insertedCount == 1)
    }

    @Test func persistImmediatelyTriggersSaveSynchronously() async {
        let store = InMemoryQueueStateStore()
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }
        let entries = [makeEntry(trackKey: "t1", title: "One")]
        _ = await queueManager.insert(
            QueueInsertRequest(mode: .playNow, entries: entries, signature: "a", requestedAt: Date(timeIntervalSince1970: 100))
        )
        store.saveCallCount = 0

        queueManager.persistImmediately()

        #expect(store.saveCallCount == 1)
    }

    @Test func snapshotReturnsCorrectStateBeforePersistFires() async {
        let store = InMemoryQueueStateStore()
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }
        let state = QueueState(
            entries: [makeEntry(trackKey: "t1", title: "One")],
            currentIndex: 0,
            elapsedTime: 42,
            isPlaying: true
        )

        _ = await queueManager.setState(state)
        let snapshot = queueManager.snapshot()

        #expect(snapshot.elapsedTime == 42)
        #expect(snapshot.currentIndex == 0)
        #expect(snapshot.entries.count == 1)
    }

    @Test func partialInsertReportsSkipReasons() async {
        let store = InMemoryQueueStateStore()
        let queueManager = QueueManager(store: store) { Date(timeIntervalSince1970: 100) }
        let playable = makeEntry(trackKey: "ok", title: "OK")
        let skippedOne = makeUnplayableEntry(trackKey: "bad1", title: "Bad 1", reason: .missingPlaybackSource)
        let skippedTwo = makeUnplayableEntry(trackKey: "bad2", title: "Bad 2", reason: .missingPlaybackSource)

        let result = await queueManager.insert(
            QueueInsertRequest(
                mode: .playNow,
                entries: [playable, skippedOne, skippedTwo],
                signature: "mix:1",
                requestedAt: Date(timeIntervalSince1970: 100)
            )
        )

        #expect(result.insertedCount == 1)
        #expect(result.skipped.count == 2)
        #expect(result.state.entries.map(\.track.ratingKey) == ["ok"])
    }
}

private func makeEntry(trackKey: String, title: String) -> QueueEntry {
    QueueEntry(
        id: UUID(),
        track: PlexTrack(
            ratingKey: trackKey,
            title: title,
            index: 1,
            parentIndex: nil,
            parentRatingKey: "album",
            duration: 1000,
            media: nil
        ),
        album: nil,
        albumRatingKeys: [],
        artworkRequest: nil,
        isPlayable: true,
        skipReason: nil
    )
}

private func makeUnplayableEntry(trackKey: String, title: String, reason: QueueInsertSkipReason) -> QueueEntry {
    QueueEntry(
        id: UUID(),
        track: PlexTrack(
            ratingKey: trackKey,
            title: title,
            index: 1,
            parentIndex: nil,
            parentRatingKey: "album",
            duration: 1000,
            media: nil
        ),
        album: nil,
        albumRatingKeys: [],
        artworkRequest: nil,
        isPlayable: false,
        skipReason: reason
    )
}

private final class InMemoryQueueStateStore: QueueStateStoring {
    private var state: QueueState?
    var saveCallCount = 0

    init(initial: QueueState? = nil) {
        self.state = initial
    }

    func load() throws -> QueueState? {
        state
    }

    func save(_ state: QueueState) throws {
        saveCallCount += 1
        self.state = state
    }

    func clear() throws {
        state = nil
    }
}
