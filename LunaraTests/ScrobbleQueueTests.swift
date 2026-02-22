import Foundation
import Testing
@testable import Lunara

@Suite
struct ScrobbleQueueTests {

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScrobbleQueueTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEntry(track: String = "Track", artist: String = "Artist", timestamp: Int = 1000) -> ScrobbleEntry {
        ScrobbleEntry(artist: artist, track: track, album: "Album", timestamp: timestamp, duration: 200)
    }

    @Test
    func enqueueAndDequeue() async {
        let queue = ScrobbleQueue(directory: makeTempDirectory())
        await queue.enqueue(makeEntry(track: "A"))
        await queue.enqueue(makeEntry(track: "B"))

        let batch = await queue.dequeue(limit: 10)
        #expect(batch.count == 2)
        #expect(batch[0].track == "A")
        #expect(batch[1].track == "B")
    }

    @Test
    func removeFront_removesCorrectCount() async {
        let queue = ScrobbleQueue(directory: makeTempDirectory())
        await queue.enqueue(makeEntry(track: "A"))
        await queue.enqueue(makeEntry(track: "B"))
        await queue.enqueue(makeEntry(track: "C"))

        await queue.removeFront(2)
        let remaining = await queue.dequeue()
        #expect(remaining.count == 1)
        #expect(remaining[0].track == "C")
    }

    @Test
    func persistence_survivesReinitialization() async {
        let dir = makeTempDirectory()
        let queue1 = ScrobbleQueue(directory: dir)
        await queue1.enqueue(makeEntry(track: "Persisted"))

        let queue2 = ScrobbleQueue(directory: dir)
        let entries = await queue2.pendingEntries
        #expect(entries.count == 1)
        #expect(entries[0].track == "Persisted")
    }

    @Test
    func dequeue_respectsLimit() async {
        let queue = ScrobbleQueue(directory: makeTempDirectory())
        for i in 0..<10 {
            await queue.enqueue(makeEntry(track: "Track\(i)"))
        }
        let batch = await queue.dequeue(limit: 3)
        #expect(batch.count == 3)
    }

    @Test
    func removeAll_clearsQueue() async {
        let queue = ScrobbleQueue(directory: makeTempDirectory())
        await queue.enqueue(makeEntry())
        await queue.enqueue(makeEntry())
        await queue.removeAll()

        #expect(await queue.pendingCount == 0)
    }
}
