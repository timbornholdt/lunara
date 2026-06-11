import Foundation
import Observation
import Testing
@testable import Lunara

@MainActor
struct AppRouterTests {
    @Test
    func playAlbum_fetchesTracksBuildsStableQueueItemsAndDoesNotResolveURLs() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-1")
        let firstTrack = makeTrack(id: "track-1", albumID: album.plexID)
        let secondTrack = makeTrack(id: "track-2", albumID: album.plexID)
        subject.library.tracksByAlbumID[album.plexID] = [firstTrack, secondTrack]

        try await subject.router.playAlbum(album)

        #expect(subject.library.trackRequests == [album.plexID])
        // URLs are resolved lazily at play time, never at queue-build time.
        #expect(subject.library.streamURLRequests.isEmpty)
        #expect(subject.queue.playNowCalls.count == 1)
        #expect(subject.queue.playNowCalls[0] == [
            expectedQueueItem(for: firstTrack),
            expectedQueueItem(for: secondTrack)
        ])
        // Queue items carry the stable stream key (track.key).
        #expect(subject.queue.playNowCalls[0].map(\.streamKey) == [firstTrack.key, secondTrack.key])
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
            QueueItem(trackID: keptTrack.plexID, streamKey: "https://example.com/\(keptTrack.plexID).mp3"),
            QueueItem(trackID: "track-missing", streamKey: "https://example.com/track-missing.mp3")
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
            streamKey: "https://example.com/track-1.mp3"
        )
        let secondItem = QueueItem(
            trackID: "track-2",
            streamKey: "https://example.com/track-2.mp3"
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
            QueueItem(trackID: "track-missing", streamKey: "https://example.com/track-missing-a.mp3"),
            QueueItem(trackID: "track-missing", streamKey: "https://example.com/track-missing-b.mp3"),
            QueueItem(trackID: "track-2", streamKey: "https://example.com/track-2.mp3")
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

        try await subject.router.queueAlbumNext(album)

        #expect(subject.queue.playNextCalls == [[expectedQueueItem(for: track)]])
    }

    @Test
    func queueAlbumLater_fetchesTracksResolvesURLsAndQueuesPlayLater() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "album-later")
        let track = makeTrack(id: "track-later", albumID: album.plexID)
        subject.library.tracksByAlbumID[album.plexID] = [track]

        try await subject.router.queueAlbumLater(album)

        #expect(subject.queue.playLaterCalls == [[expectedQueueItem(for: track)]])
    }

    @Test
    func playTrackNow_resolvesURLAndQueuesSingleItemPlayNow() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-now")

        try await subject.router.playTrackNow(track)

        #expect(subject.queue.playNowCalls == [[expectedQueueItem(for: track)]])
    }

    @Test
    func queueTrackNext_resolvesURLAndQueuesSingleItemPlayNext() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-next-single")

        try await subject.router.queueTrackNext(track)

        #expect(subject.queue.playNextCalls == [[expectedQueueItem(for: track)]])
    }

    @Test
    func queueTrackLater_resolvesURLAndQueuesSingleItemPlayLater() async throws {
        let subject = makeSubject()
        let track = makeTrack(id: "track-later-single")

        try await subject.router.queueTrackLater(track)

        #expect(subject.queue.playLaterCalls == [[expectedQueueItem(for: track)]])
    }

    @Test
    func playCollection_fetchesAlbumsTracksAndQueuesInOrder() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-1")
        let album = makeAlbum(id: "album-c1")
        let track = makeTrack(id: "track-c1", albumID: album.plexID)

        subject.library.collectionAlbumsByCollectionID[collection.plexID] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track]

        try await subject.router.playCollection(collection)

        #expect(subject.queue.playNowCalls.count == 1)
        #expect(subject.queue.playNowCalls[0] == [expectedQueueItem(for: track)])
    }

    @Test
    func shuffleCollection_fetchesAlbumsTracksAndQueuesShuffled() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-2")
        let album = makeAlbum(id: "album-c2")
        let track1 = makeTrack(id: "track-s1", albumID: album.plexID)
        let track2 = makeTrack(id: "track-s2", albumID: album.plexID)

        subject.library.collectionAlbumsByCollectionID[collection.plexID] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track1, track2]

        try await subject.router.shuffleCollection(collection)

        #expect(subject.queue.playNowCalls.count == 1)
        let allTrackIDs = Set(subject.queue.playNowCalls[0].map(\.trackID))
        #expect(allTrackIDs == Set(["track-s1", "track-s2"]))
    }

    /// A shuffle whose queue contains an already-downloaded track starts on it,
    /// so first audio comes from disk with zero network (Lunara-c48).
    @Test
    func shuffleCollection_rotatesAnOfflineTrackToTheFront() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-local")
        let albumA = makeAlbum(id: "album-streamed")
        let albumB = makeAlbum(id: "album-offline")
        subject.library.collectionAlbumsByCollectionID[collection.plexID] = [albumA, albumB]
        subject.library.tracksByAlbumID[albumA.plexID] = [
            makeTrack(id: "s1", albumID: albumA.plexID),
            makeTrack(id: "s2", albumID: albumA.plexID)
        ]
        subject.library.tracksByAlbumID[albumB.plexID] = [makeTrack(id: "local1", albumID: albumB.plexID)]
        subject.offlineStore.offlineAlbumIDs = ["album-offline"]
        subject.offlineStore.localFileURLsByTrackID["local1"] = URL(fileURLWithPath: "/tmp/local1.mp3")

        try await subject.router.shuffleCollection(collection)

        let queued = subject.queue.playNowCalls[0]
        #expect(queued.first?.trackID == "local1")
        #expect(Set(queued.map(\.trackID)) == Set(["s1", "s2", "local1"]))
    }

    /// A fully-streamed shuffle is left exactly as shuffled.
    @Test
    func shuffleCollection_withNoLocalTracks_keepsShuffledOrder() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-stream")
        let album = makeAlbum(id: "album-s")
        subject.library.collectionAlbumsByCollectionID[collection.plexID] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [
            makeTrack(id: "s1", albumID: album.plexID),
            makeTrack(id: "s2", albumID: album.plexID)
        ]

        try await subject.router.shuffleCollection(collection)

        #expect(Set(subject.queue.playNowCalls[0].map(\.trackID)) == Set(["s1", "s2"]))
    }

    /// Sequential play never reorders — the local-lead rotation is shuffle-only.
    @Test
    func playCollection_neverConsultsOfflineStoreForReordering() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-seq")
        let album = makeAlbum(id: "album-q")
        let track1 = makeTrack(id: "q1", albumID: album.plexID)
        let track2 = makeTrack(id: "q2", albumID: album.plexID)
        subject.library.collectionAlbumsByCollectionID[collection.plexID] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track1, track2]
        subject.offlineStore.offlineAlbumIDs = ["album-q"]
        subject.offlineStore.localFileURLsByTrackID["q2"] = URL(fileURLWithPath: "/tmp/q2.mp3")

        try await subject.router.playCollection(collection)

        #expect(subject.queue.playNowCalls[0].map(\.trackID) == ["q1", "q2"])
    }

    /// The multi-album queue build issues ONE batched track query, not one per
    /// album (Lunara-uuy).
    @Test
    func shuffleCollection_buildsQueueWithSingleBatchedTrackQuery() async throws {
        let subject = makeSubject()
        let collection = makeCollection(id: "col-3")
        let albumA = makeAlbum(id: "album-x")
        let albumB = makeAlbum(id: "album-y")
        subject.library.collectionAlbumsByCollectionID[collection.plexID] = [albumA, albumB]
        subject.library.tracksByAlbumID[albumA.plexID] = [makeTrack(id: "tx", albumID: albumA.plexID)]
        subject.library.tracksByAlbumID[albumB.plexID] = [makeTrack(id: "ty", albumID: albumB.plexID)]

        try await subject.router.shuffleCollection(collection)

        #expect(subject.library.batchedTracksRequests == [["album-x", "album-y"]])
        #expect(subject.library.trackRequests.isEmpty) // no per-album fallback queries
        #expect(Set(subject.queue.playNowCalls[0].map(\.trackID)) == Set(["tx", "ty"]))
    }

    @Test
    func playArtist_fetchesAlbumsTracksAndQueuesInOrder() async throws {
        let subject = makeSubject()
        let artist = makeArtist(id: "artist-1")
        let album = makeAlbum(id: "album-a1")
        let track = makeTrack(id: "track-a1", albumID: album.plexID)

        subject.library.artistAlbumsByName[artist.name] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track]

        try await subject.router.playArtist(artist)

        #expect(subject.queue.playNowCalls.count == 1)
        #expect(subject.queue.playNowCalls[0] == [expectedQueueItem(for: track)])
    }

    @Test
    func shuffleArtist_fetchesAlbumsTracksAndQueuesShuffled() async throws {
        let subject = makeSubject()
        let artist = makeArtist(id: "artist-2")
        let album = makeAlbum(id: "album-a2")
        let track1 = makeTrack(id: "track-sa1", albumID: album.plexID)
        let track2 = makeTrack(id: "track-sa2", albumID: album.plexID)

        subject.library.artistAlbumsByName[artist.name] = [album]
        subject.library.tracksByAlbumID[album.plexID] = [track1, track2]

        try await subject.router.shuffleArtist(artist)

        #expect(subject.queue.playNowCalls.count == 1)
        let allTrackIDs = Set(subject.queue.playNowCalls[0].map(\.trackID))
        #expect(allTrackIDs == Set(["track-sa1", "track-sa2"]))
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

    // NOTE: offline-vs-stream URL resolution moved out of AppRouter into
    // PlaybackURLResolver (resolved lazily at play time). See PlaybackURLResolverTests.

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

    private func makeSubject() -> (
        router: AppRouter,
        library: LibraryRepoMock,
        queue: QueueManagerMock,
        offlineStore: MockOfflineStore
    ) {
        let library = LibraryRepoMock()
        let queue = QueueManagerMock()
        let offlineStore = MockOfflineStore()
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

    private func makeTrack(id: String, albumID: String = "album-1", trackNumber: Int = 1) -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: trackNumber,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/\(id)",
            thumbURL: nil
        )
    }

    private func expectedQueueItem(for track: Track) -> QueueItem {
        QueueItem(
            trackID: track.plexID,
            streamKey: track.key,
            albumID: track.albumID,
            trackNumber: track.trackNumber,
            duration: track.duration
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

    private(set) var batchedTracksRequests: [[String]] = []

    func tracks(forAlbums albumIDs: [String]) async throws -> [Track] {
        batchedTracksRequests.append(albumIDs)
        if let tracksError {
            throw tracksError
        }
        return albumIDs.flatMap { tracksByAlbumID[$0] ?? [] }
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

    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { [] }
    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws { }

    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }

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
    var hasPlaybackBegun = false

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
    func skipTo(index: Int) {}
    func clear() {
        clearCallCount += 1
    }

    func offlineAvailabilityDidChange(forAlbums changedAlbumIDs: Set<String>) {}

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
