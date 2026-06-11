import Foundation
import MediaPlayer
import Testing
import UIKit
@testable import Lunara

@MainActor
@Suite
struct NowPlayingBridgeTests {

    @Test
    func configureDoesNotCrash() {
        let engine = PlaybackEngineMock()
        let queue = NowPlayingQueueMock()
        let library = NowPlayingLibraryMock()
        let artwork = ArtworkPipelineMock()
        let bridge = NowPlayingBridge(
            engine: engine,
            queue: queue,
            resolver: NowPlayingResolver(library: library, artwork: artwork)
        )
        bridge.configure()
    }

    @Test
    func bridgeCreatesWithAllDependencies() {
        let engine = PlaybackEngineMock()
        let queue = NowPlayingQueueMock()
        let library = NowPlayingLibraryMock()
        let artwork = ArtworkPipelineMock()
        let bridge = NowPlayingBridge(
            engine: engine,
            queue: queue,
            resolver: NowPlayingResolver(library: library, artwork: artwork)
        )
        #expect(bridge != nil)
    }

    // MARK: - Lunara-wtj: lock-screen metadata must follow the QUEUE promptly and
    // never stall behind a slow artwork fetch.

    /// Builds a configured bridge with the library seeded for the given track IDs
    /// (each track t<i> belongs to album "al-t<i>"). Returns the bridge + mocks +
    /// the QueueItems so tests can drive `queue.currentItem`.
    private func makeBridge(
        trackIDs: [String]
    ) -> (
        bridge: NowPlayingBridge,
        engine: PlaybackEngineMock,
        queue: NowPlayingQueueMock,
        library: NowPlayingLibraryMock,
        artwork: ArtworkPipelineMock,
        items: [String: QueueItem]
    ) {
        let engine = PlaybackEngineMock()
        let queue = NowPlayingQueueMock()
        let library = NowPlayingLibraryMock()
        let artwork = ArtworkPipelineMock()
        var items: [String: QueueItem] = [:]
        for id in trackIDs {
            let albumID = "al-\(id)"
            library.trackByID[id] = Track(
                plexID: id, albumID: albumID, title: "Track \(id)", trackNumber: 1,
                duration: 180, artistName: "Artist", key: "/library/metadata/\(id)", thumbURL: nil
            )
            library.albumByID[albumID] = Album(
                plexID: albumID, title: "Album \(albumID)", artistName: "Artist", year: nil,
                thumbURL: nil, genre: nil, rating: nil, addedAt: nil, trackCount: 1, duration: 180
            )
            items[id] = QueueItem(trackID: id, streamKey: "/library/metadata/\(id)", albumID: albumID)
        }
        let bridge = NowPlayingBridge(
            engine: engine, queue: queue,
            resolver: NowPlayingResolver(library: library, artwork: artwork)
        )
        return (bridge, engine, queue, library, artwork, items)
    }

    private func makeImageFile() throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try #require(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("npb-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    private func waitUntil(iterations: Int = 300, _ condition: @escaping () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test
    func trackChange_publishesNewTrack_withoutWaitingOnPendingArtwork() async {
        let env = makeBridge(trackIDs: ["t0", "t1"])
        env.artwork.gateFullSizeForOwnerID = "al-t0" // t0 artwork never returns
        env.bridge.configure()

        env.queue.currentItem = env.items["t0"]
        await waitUntil { env.artwork.fullSizeRequests.contains { $0.ownerID == "al-t0" } }

        // Skip to t1 WITHOUT releasing the t0 artwork gate.
        env.queue.currentItem = env.items["t1"]
        await waitUntil { env.artwork.fullSizeRequests.contains { $0.ownerID == "al-t1" } }

        #expect(env.artwork.fullSizeRequests.contains { $0.ownerID == "al-t1" })
        env.artwork.releaseFullSizeGate()
    }

    @Test
    func identityDrivenByQueue_notLateEngineSignal() async {
        let env = makeBridge(trackIDs: ["t0", "t1"])
        env.engine.currentTrackID = "t0" // engine lagging on the old track
        env.bridge.configure()

        env.queue.currentItem = env.items["t1"]

        await waitUntil { env.bridge.lastPublishedTrackIDForTesting == "t1" }
        #expect(env.bridge.lastPublishedTrackIDForTesting == "t1")
    }

    @Test
    func artworkApplies_whenEngineLagsBehindQueue() async throws {
        let env = makeBridge(trackIDs: ["t0", "t1"])
        let art = try makeImageFile()
        defer { try? FileManager.default.removeItem(at: art) }
        env.artwork.fullSizeResultByOwnerID["al-t1"] = art
        env.engine.currentTrackID = "t0" // engine still on the old track
        env.bridge.configure()

        env.queue.currentItem = env.items["t1"]

        await waitUntil { env.bridge.lastPublishHadArtworkForTesting }
        #expect(env.bridge.lastPublishHadArtworkForTesting)
    }

    @Test
    func rapidSkip_landsOnFinalTrack() async {
        let env = makeBridge(trackIDs: ["t0", "t1", "t2"])
        env.bridge.configure()

        env.queue.currentItem = env.items["t0"]
        env.queue.currentItem = env.items["t1"]
        env.queue.currentItem = env.items["t2"]

        await waitUntil { env.bridge.lastPublishedTrackIDForTesting == "t2" }
        #expect(env.bridge.lastPublishedTrackIDForTesting == "t2")
    }

    // Lunara-uww.7.5: artwork retries are capped at 2 (down from 3), so a track whose
    // art keeps failing settles after initial fetch + 2 retries instead of holding the
    // lock screen in a long retry tail.
    @Test
    func artworkRetry_stopsAfterTwoAttempts() async {
        let engine = PlaybackEngineMock()
        let queue = NowPlayingQueueMock()
        let library = NowPlayingLibraryMock()
        let artwork = ArtworkPipelineMock()
        library.trackByID["t0"] = Track(
            plexID: "t0", albumID: "al-t0", title: "Track t0", trackNumber: 1,
            duration: 180, artistName: "Artist", key: "/library/metadata/t0", thumbURL: nil
        )
        library.albumByID["al-t0"] = Album(
            plexID: "al-t0", title: "Album al-t0", artistName: "Artist", year: nil,
            thumbURL: nil, genre: nil, rating: nil, addedAt: nil, trackCount: 1, duration: 180
        )
        // No fullSizeResultByOwnerID seeded: every artwork fetch resolves to nil (failure).
        let bridge = NowPlayingBridge(
            engine: engine, queue: queue,
            resolver: NowPlayingResolver(library: library, artwork: artwork),
            artworkRetryBaseDelay: .zero
        )
        bridge.configure()

        queue.currentItem = QueueItem(trackID: "t0", streamKey: "/library/metadata/t0", albumID: "al-t0")

        // Initial fetch + 2 retries, then the bridge gives up.
        await waitUntil { artwork.fullSizeRequests.filter { $0.ownerID == "al-t0" }.count == 3 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(artwork.fullSizeRequests.filter { $0.ownerID == "al-t0" }.count == 3)
    }

    @Test
    func pause_doesNotRepublishOrRefetch() async {
        let env = makeBridge(trackIDs: ["t0"])
        env.bridge.configure()

        env.queue.currentItem = env.items["t0"]
        await waitUntil { env.bridge.lastPublishedTrackIDForTesting == "t0" }
        let requestsAfterPublish = env.artwork.fullSizeRequests.count

        env.engine.playbackState = .paused
        // Give any erroneous re-publish a chance to fire.
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(env.bridge.lastPublishedTrackIDForTesting == "t0")
        #expect(env.artwork.fullSizeRequests.count == requestsAfterPublish)
    }
}

// MARK: - Test Doubles

@MainActor
@Observable
final class NowPlayingQueueMock: QueueManagerProtocol {
    var items: [QueueItem] = []
    var currentIndex: Int?
    var currentItem: QueueItem?
    var lastError: MusicError?

    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var skipToNextCallCount = 0
    private(set) var skipBackCallCount = 0
    private(set) var clearCallCount = 0

    func playNow(_ items: [QueueItem]) {}
    func playNext(_ items: [QueueItem]) {}
    func playLater(_ items: [QueueItem]) {}

    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func resume() { resumeCallCount += 1 }
    func skipToNext() { skipToNextCallCount += 1 }
    func skipBack() { skipBackCallCount += 1 }
    func skipTo(index: Int) {}
    func clear() { clearCallCount += 1 }
    func reconcile(removingTrackIDs: Set<String>) {}
    func offlineAvailabilityDidChange(forAlbums changedAlbumIDs: Set<String>) {}
}

@MainActor
final class NowPlayingLibraryMock: LibraryRepoProtocol {
    var trackByID: [String: Track] = [:]
    var albumByID: [String: Album] = [:]
    private(set) var trackCallCount = 0
    private(set) var albumCallCount = 0

    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? {
        albumCallCount += 1
        return albumByID[id]
    }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }
    func tracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func track(id: String) async throws -> Track? {
        trackCallCount += 1
        return trackByID[id]
    }
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }
    func collections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }
    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { [] }
    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws { }
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(reason: reason, refreshedAt: Date(), albumCount: 0, trackCount: 0, artistCount: 0, collectionCount: 0)
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func streamURL(for track: Track) async throws -> URL { URL(string: "http://example.com")! }
}
