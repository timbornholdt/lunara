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
        queue: ScrobbleQueue
    ) {
        let engine = PlaybackEngineMock()
        let queueManager = NowPlayingQueueMock()
        let library = NowPlayingLibraryMock()
        if let track {
            library.trackByID[track.plexID] = track
        }
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
            library: library,
            client: client,
            authManager: authManager,
            scrobbleQueue: scrobbleQueue
        )
        return (manager, engine, client, scrobbleQueue)
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
