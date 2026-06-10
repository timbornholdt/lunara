import Foundation
import Testing
@testable import Lunara

/// Reproduces Lunara-2jb: when the engine auto-advances at end-of-track (the
/// crossfade flips `currentTrackID` to the next item), the Now Playing UI must
/// follow. Uses the REAL `QueueManager` so the *computed* `currentItem` and its
/// observation are exercised — a stored-property queue mock cannot reproduce the
/// observation bug.
@MainActor
struct NowPlayingAutoAdvanceTests {

    @Test
    func engineAutoAdvance_advancesQueueIndexAndUpdatesNowPlayingTitle() async throws {
        let engine = PlaybackEngineMock()
        engine.crossfadeEnabled = true
        let resolver = PlaybackURLResolvingMock()
        let queue = QueueManager(
            engine: engine,
            persistence: QueueStatePersistenceMock(),
            resolver: resolver
        )

        let library = ConfigurableLibraryRepoMock()
        for id in ["t0", "t1"] {
            let albumID = "al-\(id)"
            library.tracksByID[id] = Track(
                plexID: id, albumID: albumID, title: "Track \(id)", trackNumber: 1,
                duration: 180, artistName: "Artist", key: "/library/metadata/\(id)", thumbURL: nil
            )
            library.albumsByID[albumID] = Album(
                plexID: albumID, title: "Album \(albumID)", artistName: "Artist", year: nil,
                thumbURL: nil, genre: nil, rating: nil, addedAt: nil, trackCount: 1, duration: 180
            )
        }

        let viewModel = NowPlayingScreenViewModel(
            queueManager: queue,
            engine: engine,
            library: library,
            resolver: NowPlayingResolver(library: library, artwork: ArtworkPipelineMock())
        )

        queue.playNow([
            QueueItem(trackID: "t0", streamKey: "/library/metadata/t0", albumID: "al-t0"),
            QueueItem(trackID: "t1", streamKey: "/library/metadata/t1", albumID: "al-t1")
        ])

        // The VM resolves and shows the first track.
        await waitUntil { viewModel.trackTitle == "Track t0" }
        #expect(viewModel.trackTitle == "Track t0")

        // Simulate the engine crossfading into the next track at end-of-track:
        // completeCrossfade flips currentTrackID to t1 and resets elapsed.
        engine.elapsed = 0
        engine.currentTrackID = "t1"

        await waitUntil { queue.currentIndex == 1 && viewModel.trackTitle == "Track t1" }

        // Layer (a): the queue advanced to the new track.
        #expect(queue.currentIndex == 1)
        #expect(queue.currentItem?.trackID == "t1")
        // Layer (b): the Now Playing UI followed the advance.
        #expect(viewModel.trackTitle == "Track t1")
    }

    private func waitUntil(iterations: Int = 300, _ condition: @escaping () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            await Task.yield()
        }
    }
}
