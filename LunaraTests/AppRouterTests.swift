import Foundation
import Observation
import Testing
@testable import Lunara

@MainActor
struct AppRouterTests {
    @Test
    func resolveURL_delegatesToLibraryRepo() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-1")
        let expectedURL = try #require(URL(string: "https://example.com/stream/track-1.mp3"))
        subject.library.streamURLByTrackID[track.plexID] = expectedURL

        let resolvedURL = try await subject.router.resolveURL(for: track)

        #expect(resolvedURL == expectedURL)
        #expect(subject.library.streamURLRequests == [track.plexID])
    }

    @Test
    func playAlbum_fetchesTracksResolvesURLsAndQueuesPlayNow() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-1")
        let firstTrack = makeTrack(id: "track-1", albumID: album.plexID)
        let secondTrack = makeTrack(id: "track-2", albumID: album.plexID)
        subject.library.tracksByAlbumID[album.plexID] = [firstTrack, secondTrack]
        subject.library.streamURLByTrackID[firstTrack.plexID] = try #require(URL(string: "https://example.com/stream/track-1.mp3"))
        subject.library.streamURLByTrackID[secondTrack.plexID] = try #require(URL(string: "https://example.com/stream/track-2.mp3"))

        try await subject.router.playAlbum(album)

        #expect(subject.library.trackRequests == [album.plexID])
        #expect(subject.library.streamURLRequests == [firstTrack.plexID, secondTrack.plexID])
        #expect(subject.queue.playNowCalls.count == 1)
        #expect(subject.queue.playNowCalls[0] == [
            QueueItem(trackID: firstTrack.plexID, url: try #require(subject.library.streamURLByTrackID[firstTrack.plexID])),
            QueueItem(trackID: secondTrack.plexID, url: try #require(subject.library.streamURLByTrackID[secondTrack.plexID]))
        ])
    }

    @Test
    func playAlbum_whenTrackFetchFails_propagatesErrorAndDoesNotQueue() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-2")
        subject.library.tracksError = LibraryError.plexUnreachable

        do {
            try await subject.router.playAlbum(album)
            Issue.record("Expected playAlbum to throw")
        } catch let error as LibraryError {
            #expect(error == .plexUnreachable)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(subject.queue.playNowCalls.isEmpty)
        #expect(subject.library.streamURLRequests.isEmpty)
    }

    @Test
    func playAlbum_whenAlbumHasNoTracks_throwsResourceNotFoundAndDoesNotMutateQueue() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-empty")
        subject.library.tracksByAlbumID[album.plexID] = []

        do {
            try await subject.router.playAlbum(album)
            Issue.record("Expected playAlbum to throw for empty album")
        } catch let error as LibraryError {
            #expect(error == .resourceNotFound(type: "tracks", id: album.plexID))
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(subject.library.trackRequests == [album.plexID])
        #expect(subject.library.streamURLRequests.isEmpty)
        #expect(subject.queue.playNowCalls.isEmpty)
    }

    @Test
    func playAlbum_whenURLResolutionFails_propagatesErrorAndDoesNotQueue() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-3")
        let track = makeTrack(id: "track-3", albumID: album.plexID)
        subject.library.tracksByAlbumID[album.plexID] = [track]
        subject.library.streamURLError = LibraryError.timeout

        do {
            try await subject.router.playAlbum(album)
            Issue.record("Expected playAlbum to throw")
        } catch let error as LibraryError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(subject.queue.playNowCalls.isEmpty)
        #expect(subject.library.streamURLRequests == [track.plexID])
    }

    @Test
    func pausePlayback_delegatesToQueuePause() {
        let subject = makeSubject()

        subject.router.pausePlayback()

        #expect(subject.queue.pauseCallCount == 1)
    }

    @Test
    func resumePlayback_delegatesToQueueResume() {
        let subject = makeSubject()

        subject.router.resumePlayback()

        #expect(subject.queue.resumeCallCount == 1)
    }

    @Test
    func skipToNextTrack_delegatesToQueueSkipToNext() {
        let subject = makeSubject()

        subject.router.skipToNextTrack()

        #expect(subject.queue.skipToNextCallCount == 1)
    }

    @Test
    func stopPlayback_delegatesToQueueClear() {
        let subject = makeSubject()

        subject.router.stopPlayback()

        #expect(subject.queue.clearCallCount == 1)
    }

    @Test
    func queueAlbumNext_fetchesTracksResolvesURLsAndQueuesPlayNext() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-next")
        let track = makeTrack(id: "track-next", albumID: album.plexID)
        subject.library.tracksByAlbumID[album.plexID] = [track]
        let streamURL = try #require(URL(string: "https://example.com/stream/track-next.mp3"))
        subject.library.streamURLByTrackID[track.plexID] = streamURL

        try await subject.router.queueAlbumNext(album)

        #expect(subject.queue.playNextCalls == [[QueueItem(trackID: track.plexID, url: streamURL)]])
    }

    @Test
    func queueAlbumLater_fetchesTracksResolvesURLsAndQueuesPlayLater() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-later")
        let track = makeTrack(id: "track-later", albumID: album.plexID)
        subject.library.tracksByAlbumID[album.plexID] = [track]
        let streamURL = try #require(URL(string: "https://example.com/stream/track-later.mp3"))
        subject.library.streamURLByTrackID[track.plexID] = streamURL

        try await subject.router.queueAlbumLater(album)

        #expect(subject.queue.playLaterCalls == [[QueueItem(trackID: track.plexID, url: streamURL)]])
    }

    @Test
    func playTrackNow_resolvesURLAndQueuesSingleItemPlayNow() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-now")
        let streamURL = try #require(URL(string: "https://example.com/stream/track-now.mp3"))
        subject.library.streamURLByTrackID[track.plexID] = streamURL

        try await subject.router.playTrackNow(track)

        #expect(subject.queue.playNowCalls == [[QueueItem(trackID: track.plexID, url: streamURL)]])
    }

    @Test
    func queueTrackNext_resolvesURLAndQueuesSingleItemPlayNext() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-next-single")
        let streamURL = try #require(URL(string: "https://example.com/stream/track-next-single.mp3"))
        subject.library.streamURLByTrackID[track.plexID] = streamURL

        try await subject.router.queueTrackNext(track)

        #expect(subject.queue.playNextCalls == [[QueueItem(trackID: track.plexID, url: streamURL)]])
    }

    @Test
    func queueTrackLater_resolvesURLAndQueuesSingleItemPlayLater() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-later-single")
        let streamURL = try #require(URL(string: "https://example.com/stream/track-later-single.mp3"))
        subject.library.streamURLByTrackID[track.plexID] = streamURL

        try await subject.router.queueTrackLater(track)

        #expect(subject.queue.playLaterCalls == [[QueueItem(trackID: track.plexID, url: streamURL)]])
    }

    private func makeSubject() -> (
        router: AppRouter,
        library: LibraryRepoMock,
        queue: QueueManagerMock
    ) {
        let library = LibraryRepoMock()
        let queue = QueueManagerMock()
        let router = AppRouter(library: library, queue: queue)
        return (router, library, queue)
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
            trackCount: 0,
            duration: 0
        )
    }

    private func makeTrack(id: String, albumID: String = "album-1") -> Track {
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
}

@MainActor
private final class LibraryRepoMock: LibraryRepoProtocol {
    var albums: [Album] = []
    var albumPageRequests: [LibraryPage] = []

    var tracksByAlbumID: [String: [Track]] = [:]
    var trackRequests: [String] = []
    var tracksError: LibraryError?

    var streamURLByTrackID: [String: URL] = [:]
    var streamURLRequests: [String] = []
    var streamURLError: LibraryError?

    func albums(page: LibraryPage) async throws -> [Album] {
        albumPageRequests.append(page)

        guard page.offset < albums.count else {
            return []
        }

        let endIndex = min(page.offset + page.size, albums.count)
        return Array(albums[page.offset..<endIndex])
    }

    func album(id: String) async throws -> Album? {
        albums.first { $0.plexID == id }
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        trackRequests.append(albumID)
        if let tracksError {
            throw tracksError
        }
        return tracksByAlbumID[albumID] ?? []
    }

    func streamURL(for track: Track) async throws -> URL {
        streamURLRequests.append(track.plexID)
        if let streamURLError {
            throw streamURLError
        }
        guard let url = streamURLByTrackID[track.plexID] else {
            throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
        }
        return url
    }

    func collections() async throws -> [Collection] {
        []
    }

    func artists() async throws -> [Artist] {
        []
    }

    func artist(id: String) async throws -> Artist? {
        nil
    }

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(
            reason: reason,
            refreshedAt: Date(timeIntervalSince1970: 0),
            albumCount: 0,
            trackCount: 0,
            artistCount: 0,
            collectionCount: 0
        )
    }

    func lastRefreshDate() async throws -> Date? {
        nil
    }
}

@MainActor
@Observable
private final class QueueManagerMock: QueueManagerProtocol {
    private(set) var items: [QueueItem] = []
    private(set) var currentIndex: Int?
    private(set) var currentItem: QueueItem?
    private(set) var lastError: MusicError?

    private(set) var playNowCalls: [[QueueItem]] = []
    private(set) var playNextCalls: [[QueueItem]] = []
    private(set) var playLaterCalls: [[QueueItem]] = []
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var skipToNextCallCount = 0
    private(set) var clearCallCount = 0

    func playNow(_ items: [QueueItem]) {
        playNowCalls.append(items)
        self.items = items
        currentIndex = items.isEmpty ? nil : 0
        currentItem = items.first
    }

    func playNext(_ items: [QueueItem]) {
        playNextCalls.append(items)
    }
    func playLater(_ items: [QueueItem]) {
        playLaterCalls.append(items)
    }
    func play() { }
    func pause() {
        pauseCallCount += 1
    }
    func resume() {
        resumeCallCount += 1
    }
    func skipToNext() {
        skipToNextCallCount += 1
    }
    func clear() {
        clearCallCount += 1
    }
}
