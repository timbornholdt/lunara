import Foundation
import Testing
@testable import Lunara

/// Acceptance test for Lunara-uww.7.1: the now-playing screen, bar, and lock-screen
/// bridge share ONE `NowPlayingResolver`, so a single track change resolves the
/// track and album exactly once across all three consumers instead of 3× each.
@MainActor
struct NowPlayingResolverDedupTests {
    private func makeQueueItem(trackID: String) -> QueueItem {
        QueueItem(trackID: trackID, streamKey: "/library/metadata/\(trackID)")
    }

    private func makeTrack(id: String, albumID: String) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: 1,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/\(id)",
            thumbURL: nil
        )
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 1,
            duration: 180
        )
    }

    private func waitUntil(iterations: Int = 300, _ condition: @escaping () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test
    func singleTrackChangeResolvesTrackAndAlbumOnceAcrossAllConsumers() async {
        let library = ConfigurableLibraryRepoMock()
        library.tracksByID["t0"] = makeTrack(id: "t0", albumID: "al0")
        library.albumsByID["al0"] = makeAlbum(id: "al0")
        let artwork = ArtworkPipelineMock()
        let resolver = NowPlayingResolver(library: library, artwork: artwork)

        // Single-item queue: the only resolvable track is the current one, so any
        // extra track/album request would be a genuine duplicate, not up-next work.
        let queue = NowPlayingQueueMock()
        let item = makeQueueItem(trackID: "t0")
        queue.items = [item]
        queue.currentIndex = 0
        queue.currentItem = item

        let bar = NowPlayingBarViewModel(
            queueManager: queue,
            engine: PlaybackEngineMock(),
            resolver: resolver
        )
        let screen = NowPlayingScreenViewModel(
            queueManager: queue,
            engine: PlaybackEngineMock(),
            library: library,
            resolver: resolver
        )
        let bridge = NowPlayingBridge(
            engine: PlaybackEngineMock(),
            queue: queue,
            resolver: resolver
        )
        bridge.configure()

        await waitUntil { library.trackRequests.contains("t0") }
        // Let every consumer's resolution settle so any duplicate would have landed.
        try? await Task.sleep(nanoseconds: 250_000_000)

        #expect(library.trackRequests.filter { $0 == "t0" }.count == 1)
        #expect(library.albumRequests.filter { $0 == "al0" }.count == 1)

        // Keep the consumers alive until the assertions run.
        _ = (bar, screen, bridge)
    }
}
