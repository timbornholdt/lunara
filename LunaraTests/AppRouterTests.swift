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
    func reconcileQueueAgainstLibrary_removesMissingTrackIDsFromQueue() async throws {
        let subject = makeSubject()
        let keptTrack = makeTrack(id: "track-kept")
        subject.library.trackByID[keptTrack.plexID] = keptTrack
        subject.queue.playNow([
            QueueItem(trackID: keptTrack.plexID, url: try #require(URL(string: "https://example.com/\(keptTrack.plexID).mp3"))),
            QueueItem(trackID: "track-missing", url: try #require(URL(string: "https://example.com/track-missing.mp3")))
        ])

        let outcome = try await subject.router.reconcileQueueAgainstLibrary()

        #expect(outcome.removedTrackIDs == ["track-missing"])
        #expect(outcome.removedItemCount == 1)
        #expect(subject.library.trackLookupRequests == [keptTrack.plexID, "track-missing"])
        #expect(subject.queue.reconcileCalls == [Set(["track-missing"])])
        #expect(subject.queue.items.map(\.trackID) == [keptTrack.plexID])
    }

    @Test
    func reconcileQueueAgainstLibrary_whenLookupFails_doesNotMutateQueue() async throws {
        let subject = makeSubject()
        let firstItem = QueueItem(
            trackID: "track-1",
            url: try #require(URL(string: "https://example.com/track-1.mp3"))
        )
        let secondItem = QueueItem(
            trackID: "track-2",
            url: try #require(URL(string: "https://example.com/track-2.mp3"))
        )
        subject.queue.playNow([firstItem, secondItem])
        subject.library.trackLookupErrorByID["track-2"] = LibraryError.timeout
        subject.library.trackByID["track-1"] = makeTrack(id: "track-1")

        do {
            _ = try await subject.router.reconcileQueueAgainstLibrary()
            Issue.record("Expected reconcileQueueAgainstLibrary to throw")
        } catch let error as LibraryError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(subject.queue.reconcileCalls.isEmpty)
        #expect(subject.queue.items == [firstItem, secondItem])
    }

    @Test
    func reconcileQueueAgainstLibrary_withDuplicateTrackIDs_performsSingleLookupAndRemovesAllOccurrences() async throws {
        let subject = makeSubject()
        subject.library.trackByID["track-2"] = makeTrack(id: "track-2")
        subject.queue.playNow([
            QueueItem(trackID: "track-missing", url: try #require(URL(string: "https://example.com/track-missing-a.mp3"))),
            QueueItem(trackID: "track-missing", url: try #require(URL(string: "https://example.com/track-missing-b.mp3"))),
            QueueItem(trackID: "track-2", url: try #require(URL(string: "https://example.com/track-2.mp3")))
        ])

        let outcome = try await subject.router.reconcileQueueAgainstLibrary()

        #expect(outcome.removedTrackIDs == ["track-missing"])
        #expect(outcome.removedItemCount == 2)
        #expect(subject.library.trackLookupRequests == ["track-missing", "track-2"])
        #expect(subject.queue.reconcileCalls == [Set(["track-missing"])])
        #expect(subject.queue.items.map(\.trackID) == ["track-2"])
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

    @Test
    func playCollection_fetchesAlbumsTracksAndQueuesInOrder() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-1")
        let album = makeAlbum(id: "album-c1")
        let track = makeTrack(id: "track-c1", albumID: album.plexID)
        let streamURL = try #require(URL(string: "https://example.com/stream/track-c1.mp3"))

        subject.library.collectionAlbumsByCollectionID[collection.plexID] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track]
        subject.library.streamURLByTrackID[track.plexID] = streamURL

        try await subject.router.playCollection(collection)

        #expect(subject.queue.playNowCalls.count == 1)
        #expect(subject.queue.playNowCalls[0] == [QueueItem(trackID: track.plexID, url: streamURL)])
    }

    @Test
    func shuffleCollection_fetchesAlbumsTracksAndQueuesShuffled() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-2")
        let album = makeAlbum(id: "album-c2")
        let track1 = makeTrack(id: "track-s1", albumID: album.plexID)
        let track2 = makeTrack(id: "track-s2", albumID: album.plexID)
        let url1 = try #require(URL(string: "https://example.com/stream/track-s1.mp3"))
        let url2 = try #require(URL(string: "https://example.com/stream/track-s2.mp3"))

        subject.library.collectionAlbumsByCollectionID[collection.plexID] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track1, track2]
        subject.library.streamURLByTrackID[track1.plexID] = url1
        subject.library.streamURLByTrackID[track2.plexID] = url2

        try await subject.router.shuffleCollection(collection)

        #expect(subject.queue.playNowCalls.count == 1)
        let queuedTrackIDs = Set(subject.queue.playNowCalls[0].map(\.trackID))
        #expect(queuedTrackIDs == Set(["track-s1", "track-s2"]))
    }

    @Test
    func playArtist_fetchesAlbumsTracksAndQueuesInOrder() async throws {
        let subject = makeSubject()
        let artist = makeArtist(id: "artist-1")
        let album = makeAlbum(id: "album-a1")
        let track = makeTrack(id: "track-a1", albumID: album.plexID)
        let streamURL = try #require(URL(string: "https://example.com/stream/track-a1.mp3"))

        subject.library.artistAlbumsByName[artist.name] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track]
        subject.library.streamURLByTrackID[track.plexID] = streamURL

        try await subject.router.playArtist(artist)

        #expect(subject.queue.playNowCalls.count == 1)
        #expect(subject.queue.playNowCalls[0] == [QueueItem(trackID: track.plexID, url: streamURL)])
    }

    @Test
    func shuffleArtist_fetchesAlbumsTracksAndQueuesShuffled() async throws {
        let subject = makeSubject()
        let artist = makeArtist(id: "artist-2")
        let album = makeAlbum(id: "album-a2")
        let track1 = makeTrack(id: "track-sa1", albumID: album.plexID)
        let track2 = makeTrack(id: "track-sa2", albumID: album.plexID)
        let url1 = try #require(URL(string: "https://example.com/stream/track-sa1.mp3"))
        let url2 = try #require(URL(string: "https://example.com/stream/track-sa2.mp3"))

        subject.library.artistAlbumsByName[artist.name] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track1, track2]
        subject.library.streamURLByTrackID[track1.plexID] = url1
        subject.library.streamURLByTrackID[track2.plexID] = url2

        try await subject.router.shuffleArtist(artist)

        #expect(subject.queue.playNowCalls.count == 1)
        let queuedTrackIDs = Set(subject.queue.playNowCalls[0].map(\.trackID))
        #expect(queuedTrackIDs == Set(["track-sa1", "track-sa2"]))
    }

    @Test
    func playArtist_whenNoAlbums_throwsResourceNotFound() async {
        let subject = makeSubject()
        let artist = makeArtist(id: "artist-empty")
        subject.library.artistAlbumsByName[artist.name] = []

        do {
            try await subject.router.playArtist(artist)
            Issue.record("Expected playArtist to throw")
        } catch let error as LibraryError {
            #expect(error == .resourceNotFound(type: "albums", id: artist.plexID))
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(subject.queue.playNowCalls.isEmpty)
    }

    @Test
    func playCollection_whenNoAlbums_throwsResourceNotFound() async {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-empty")
        subject.library.collectionAlbumsByCollectionID[collection.plexID] = []

        do {
            try await subject.router.playCollection(collection)
            Issue.record("Expected playCollection to throw")
        } catch let error as LibraryError {
            #expect(error == .resourceNotFound(type: "albums", id: collection.plexID))
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(subject.queue.playNowCalls.isEmpty)
    }

    @Test
    func resolveURL_returnsLocalFileWhenOfflineTrackExists() async throws {
        let offlineStore = MockOfflineStore()
        let subject = makeSubject(offlineStore: offlineStore)
        let track = makeTrack(id: "track-offline")
        let localURL = try #require(URL(string: "file:///offline/track-offline.flac"))
        offlineStore.localFileURLsByTrackID[track.plexID] = localURL

        let resolvedURL = try await subject.router.resolveURL(for: track)

        #expect(resolvedURL == localURL)
        // Should NOT have called streamURL
        #expect(subject.library.streamURLRequests.isEmpty)
    }

    @Test
    func resolveURL_fallsBackToStreamWhenNoOfflineTrack() async throws {
        let offlineStore = MockOfflineStore()
        let subject = makeSubject(offlineStore: offlineStore)
        let track = makeTrack(id: "track-stream")
        let streamURL = try #require(URL(string: "https://example.com/stream/track-stream.mp3"))
        subject.library.streamURLByTrackID[track.plexID] = streamURL

        let resolvedURL = try await subject.router.resolveURL(for: track)

        #expect(resolvedURL == streamURL)
        #expect(subject.library.streamURLRequests == [track.plexID])
    }

    private func makeCollection(id: String) -> Collection {
        Collection(
            plexID: id,
            title: "Collection \(id)",
            thumbURL: nil,
            summary: nil,
            albumCount: 5,
            updatedAt: nil
        )
    }

    private func makeSubject(offlineStore: MockOfflineStore? = nil) -> (
        router: AppRouter,
        library: LibraryRepoMock,
        queue: QueueManagerMock,
        offlineStore: MockOfflineStore?
    ) {
        let library = LibraryRepoMock()
        let queue = QueueManagerMock()
        let router = AppRouter(library: library, queue: queue, offlineStore: offlineStore)
        return (router, library, queue, offlineStore)
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

    private func makeArtist(id: String) -> Artist {
        Artist(
            plexID: id,
            name: "Artist \(id)",
            sortName: nil,
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 0
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
    var trackByID: [String: Track] = [:]
    var trackLookupRequests: [String] = []
    var trackLookupErrorByID: [String: Error] = [:]
    var queriedAlbumsByFilter: [AlbumQueryFilter: [Album]] = [:]

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

    func searchAlbums(query: String) async throws -> [Album] {
        []
    }

    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        queriedAlbumsByFilter[filter] ?? []
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        trackRequests.append(albumID)
        if let tracksError {
            throw tracksError
        }
        return tracksByAlbumID[albumID] ?? []
    }

    func track(id: String) async throws -> Track? {
        trackLookupRequests.append(id)
        if let error = trackLookupErrorByID[id] {
            throw error
        }
        return trackByID[id]
    }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: tracksByAlbumID[albumID] ?? [])
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

    func collection(id: String) async throws -> Collection? {
        nil
    }

    var collectionAlbumsByCollectionID: [String: [Album]] = [:]

    func collectionAlbums(collectionID: String) async throws -> [Album] {
        collectionAlbumsByCollectionID[collectionID] ?? []
    }

    func searchCollections(query: String) async throws -> [Collection] {
        []
    }

    func artists() async throws -> [Artist] {
        []
    }

    func artist(id: String) async throws -> Artist? {
        nil
    }

    func searchArtists(query: String) async throws -> [Artist] {
        []
    }

    var artistAlbumsByName: [String: [Album]] = [:]
    func artistAlbums(artistName: String) async throws -> [Album] {
        artistAlbumsByName[artistName] ?? []
    }

    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }

    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }

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

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
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
    private(set) var reconcileCalls: [Set<String>] = []

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
    func skipBack() {}
    func clear() {
        clearCallCount += 1
    }

    func reconcile(removingTrackIDs: Set<String>) {
        reconcileCalls.append(removingTrackIDs)
        guard !removingTrackIDs.isEmpty else { return }
        items.removeAll { removingTrackIDs.contains($0.trackID) }
        if items.isEmpty {
            currentIndex = nil
            currentItem = nil
        } else if let currentIndex, items.indices.contains(currentIndex) {
            currentItem = items[currentIndex]
        } else {
            self.currentIndex = 0
            currentItem = items.first
        }
    }
}
