import Foundation
import Testing
@testable import Lunara

@MainActor
@Suite
struct ScrobbleManagerTests {

    private func makeTrack(id: String = "track-1", duration: TimeInterval = 200) -> Track {
        Track(
            plexID: id,
            albumID: "album-1",
            title: "Test Track",
            trackNumber: 1,
            duration: duration,
            artistName: "Test Artist",
            key: "/library/metadata/\(id)",
            thumbURL: nil
        )
    }

    private func makeSubject(
        track: Track? = nil,
        isAuthenticated: Bool = true,
        scrobblingEnabled: Bool = true
    ) -> (
        manager: ScrobbleManager,
        engine: PlaybackEngineMock,
        client: LastFMClientMock,
        queue: ScrobbleQueue,
        library: NowPlayingLibraryMock,
        resolver: NowPlayingResolver
    ) {
        let engine = PlaybackEngineMock()
        let queueManager = NowPlayingQueueMock()
        let library = NowPlayingLibraryMock()
        if let track {
            library.trackByID[track.plexID] = track
            library.albumByID[track.albumID] = Album(
                plexID: track.albumID, title: "Test Album", artistName: track.artistName, year: nil,
                thumbURL: nil, genre: nil, rating: nil, addedAt: nil, trackCount: 1, duration: track.duration
            )
        }
        let resolver = NowPlayingResolver(library: library, artwork: ArtworkPipelineMock())
        let client = LastFMClientMock()
        let keychain = MockKeychainHelper()
        if isAuthenticated {
            try? keychain.save(key: "lastfm_session_key", string: "test-session")
            try? keychain.save(key: "lastfm_username", string: "test-user")
        }
        let authManager = LastFMAuthManager(client: client, keychain: keychain, urlOpener: URLOpenerMock())
        let scrobbleQueue = ScrobbleQueue(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

        var settings = LastFMSettings(isEnabled: scrobblingEnabled)
        settings.save()

        let manager = ScrobbleManager(
            engine: engine,
            queue: queueManager,
            resolver: resolver,
            client: client,
            authManager: authManager,
            scrobbleQueue: scrobbleQueue
        )
        return (manager, engine, client, scrobbleQueue, library, resolver)
    }

    private func waitUntil(iterations: Int = 300, _ condition: @escaping () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test
    func scrobbleManager_createsWithoutCrash() {
        let track = makeTrack()
        let subject = makeSubject(track: track)
        #expect(subject.manager != nil)
    }

    @Test
    func flushQueue_sendsQueuedScrobbles() async {
        let track = makeTrack()
        let subject = makeSubject(track: track)
        let entry = ScrobbleEntry(artist: "Artist", track: "Track", album: "Album", timestamp: 1000, duration: 200)
        await subject.queue.enqueue(entry)

        await subject.manager.flushQueue()

        #expect(subject.client.scrobbleCalls.count == 1)
        #expect(await subject.queue.pendingCount == 0)
    }

    @Test
    func flushQueue_doesNothingWhenNotAuthenticated() async {
        let subject = makeSubject(isAuthenticated: false)
        let entry = ScrobbleEntry(artist: "Artist", track: "Track", album: "Album", timestamp: 1000, duration: 200)
        await subject.queue.enqueue(entry)

        await subject.manager.flushQueue()

        #expect(subject.client.scrobbleCalls.isEmpty)
        #expect(await subject.queue.pendingCount == 1)
    }

    // Lunara-0hp: scrobble lookups ride the shared NowPlayingResolver cache, so a
    // track the now-playing UI already resolved is NOT re-fetched from the library.
    @Test
    func sendNowPlaying_reusesSharedResolverCache() async {
        let track = makeTrack()
        let subject = makeSubject(track: track)

        // Warm the shared resolver the way the now-playing screen/bar/bridge would.
        _ = await subject.resolver.track(id: track.plexID)
        if let warmed = await subject.resolver.track(id: track.plexID) {
            _ = await subject.resolver.album(id: warmed.albumID)
        }
        let trackCallsAfterWarm = subject.library.trackCallCount
        let albumCallsAfterWarm = subject.library.albumCallCount

        subject.engine.currentTrackID = track.plexID
        subject.engine.playbackState = .playing
        subject.manager.configure()
        await waitUntil { subject.client.nowPlayingCalls.count == 1 }

        #expect(subject.client.nowPlayingCalls.count == 1)
        #expect(subject.client.nowPlayingCalls.first?.track == track.title)
        // Served from the resolver's memo — no additional library round-trips.
        #expect(subject.library.trackCallCount == trackCallsAfterWarm)
        #expect(subject.library.albumCallCount == albumCallsAfterWarm)
    }

    @Test
    func flushQueue_keepsEntriesOnAPIFailure() async {
        let track = makeTrack()
        let subject = makeSubject(track: track)
        subject.client.scrobbleError = LastFMError.networkError("offline")
        let entry = ScrobbleEntry(artist: "Artist", track: "Track", album: "Album", timestamp: 1000, duration: 200)
        await subject.queue.enqueue(entry)

        await subject.manager.flushQueue()

        #expect(await subject.queue.pendingCount == 1)
    }
}
