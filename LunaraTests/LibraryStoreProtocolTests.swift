import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryStoreProtocolTests {
    @Test
    func libraryPage_clampsInvalidInputsToMinimumValues() {
        let page = LibraryPage(number: 0, size: 0)

        #expect(page.number == 1)
        #expect(page.size == 1)
        #expect(page.offset == 0)
    }

    @Test
    func libraryPage_computesOffsetUsingOneBasedPageNumbers() {
        let page = LibraryPage(number: 3, size: 50)

        #expect(page.offset == 100)
    }

    @Test
    func librarySnapshot_isEmptyOnlyWhenAllCollectionsAreEmpty() {
        let empty = LibrarySnapshot(albums: [], tracks: [], artists: [], collections: [])
        let populated = LibrarySnapshot(
            albums: [makeAlbum(id: "album-1")],
            tracks: [],
            artists: [],
            collections: []
        )

        #expect(empty.isEmpty)
        #expect(!populated.isEmpty)
    }

    @Test
    func librarySnapshot_tracksForAlbum_filtersByAlbumAndSortsByTrackNumber() {
        let snapshot = LibrarySnapshot(
            albums: [],
            tracks: [
                makeTrack(id: "track-2", albumID: "album-a", trackNumber: 2),
                makeTrack(id: "track-1", albumID: "album-a", trackNumber: 1),
                makeTrack(id: "track-9", albumID: "album-b", trackNumber: 9)
            ],
            artists: [],
            collections: []
        )

        let albumTracks = snapshot.tracks(forAlbumID: "album-a")

        #expect(albumTracks.map(\.plexID) == ["track-1", "track-2"])
    }

    @Test
    func librarySyncRun_init_setsStableIDAndStartTimestamp() {
        let start = Date(timeIntervalSince1970: 1234)
        let run = LibrarySyncRun(id: "sync-1", startedAt: start)

        #expect(run.id == "sync-1")
        #expect(run.startedAt == start)
    }

    @Test
    func librarySyncPruneResult_isEmptyOnlyWhenNoAlbumsOrTracksWerePruned() {
        let empty = LibrarySyncPruneResult.empty
        let prunedTracksOnly = LibrarySyncPruneResult(prunedAlbumIDs: [], prunedTrackIDs: ["track-1"])

        #expect(empty.isEmpty)
        #expect(!prunedTracksOnly.isEmpty)
    }

    @Test
    func librarySyncCheckpoint_preservesKeyValueAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 2222)
        let checkpoint = LibrarySyncCheckpoint(
            key: "albums.lastSeenCursor",
            value: "cursor-42",
            updatedAt: timestamp
        )

        #expect(checkpoint.key == "albums.lastSeenCursor")
        #expect(checkpoint.value == "cursor-42")
        #expect(checkpoint.updatedAt == timestamp)
    }

    @Test
    func queryServiceAPIs_recordSearchQueriesAndLookupIDs() async throws {
        let store = ProtocolStoreMock()
        let expectedTrack = makeTrack(id: "track-1", albumID: "album-1", trackNumber: 1)
        let expectedCollection = Collection(
            plexID: "collection-1",
            title: "Collection 1",
            thumbURL: nil,
            summary: nil,
            albumCount: 5,
            updatedAt: nil
        )
        store.searchedAlbumsByQuery["blue"] = [makeAlbum(id: "album-1")]
        store.searchedArtistsByQuery["davis"] = [Artist(
            plexID: "artist-1",
            name: "Miles Davis",
            sortName: "Davis, Miles",
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 20
        )]
        store.searchedCollectionsByQuery["jazz"] = [expectedCollection]
        store.trackByID[expectedTrack.plexID] = expectedTrack
        store.collectionByID[expectedCollection.plexID] = expectedCollection

        let albums = try await store.searchAlbums(query: "blue")
        let artists = try await store.searchArtists(query: "davis")
        let collections = try await store.searchCollections(query: "jazz")
        let track = try await store.track(id: "track-1")
        let collection = try await store.collection(id: "collection-1")

        #expect(store.searchAlbumQueries == ["blue"])
        #expect(store.searchArtistQueries == ["davis"])
        #expect(store.searchCollectionQueries == ["jazz"])
        #expect(store.trackLookupRequests == ["track-1"])
        #expect(store.collectionLookupRequests == ["collection-1"])
        #expect(albums.map(\.plexID) == ["album-1"])
        #expect(artists.map(\.plexID) == ["artist-1"])
        #expect(collections.map(\.plexID) == ["collection-1"])
        #expect(track?.plexID == "track-1")
        #expect(collection?.plexID == "collection-1")
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: 2020,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )
    }

    private func makeTrack(id: String, albumID: String, trackNumber: Int) -> Track {
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
}

@MainActor
private final class ProtocolStoreMock: LibraryStoreProtocol {
    var searchedAlbumsByQuery: [String: [Album]] = [:]
    var searchedArtistsByQuery: [String: [Artist]] = [:]
    var searchedCollectionsByQuery: [String: [Collection]] = [:]
    var trackByID: [String: Track] = [:]
    var collectionByID: [String: Collection] = [:]
    var searchAlbumQueries: [String] = []
    var searchArtistQueries: [String] = []
    var searchCollectionQueries: [String] = []
    var trackLookupRequests: [String] = []
    var collectionLookupRequests: [String] = []

    func fetchAlbums(page: LibraryPage) async throws -> [Album] { [] }
    func fetchAlbum(id: String) async throws -> Album? { nil }
    func upsertAlbum(_ album: Album) async throws { }
    func fetchTracks(forAlbum albumID: String) async throws -> [Track] { [] }
    func replaceTracks(_ tracks: [Track], forAlbum albumID: String) async throws { }
    func track(id: String) async throws -> Track? {
        trackLookupRequests.append(id)
        return trackByID[id]
    }
    func fetchArtists() async throws -> [Artist] { [] }
    func fetchArtist(id: String) async throws -> Artist? { nil }
    func fetchCollections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? {
        collectionLookupRequests.append(id)
        return collectionByID[id]
    }
    func searchAlbums(query: String) async throws -> [Album] {
        searchAlbumQueries.append(query)
        return searchedAlbumsByQuery[query] ?? []
    }
    func searchArtists(query: String) async throws -> [Artist] {
        searchArtistQueries.append(query)
        return searchedArtistsByQuery[query] ?? []
    }
    func searchCollections(query: String) async throws -> [Collection] {
        searchCollectionQueries.append(query)
        return searchedCollectionsByQuery[query] ?? []
    }
    func replaceLibrary(with snapshot: LibrarySnapshot, refreshedAt: Date) async throws { }
    func lastRefreshDate() async throws -> Date? { nil }
    func beginIncrementalSync(startedAt: Date) async throws -> LibrarySyncRun {
        LibrarySyncRun(id: "mock", startedAt: startedAt)
    }
    func upsertAlbums(_ albums: [Album], in run: LibrarySyncRun) async throws { }
    func upsertTracks(_ tracks: [Track], in run: LibrarySyncRun) async throws { }
    func markAlbumsSeen(_ albumIDs: [String], in run: LibrarySyncRun) async throws { }
    func markTracksSeen(_ trackIDs: [String], in run: LibrarySyncRun) async throws { }
    func pruneRowsNotSeen(in run: LibrarySyncRun) async throws -> LibrarySyncPruneResult { .empty }
    func setSyncCheckpoint(_ checkpoint: LibrarySyncCheckpoint, in run: LibrarySyncRun?) async throws { }
    func syncCheckpoint(forKey key: String) async throws -> LibrarySyncCheckpoint? { nil }
    func completeIncrementalSync(_ run: LibrarySyncRun, refreshedAt: Date) async throws { }
    func artworkPath(for key: ArtworkKey) async throws -> String? { nil }
    func setArtworkPath(_ path: String, for key: ArtworkKey) async throws { }
    func deleteArtworkPath(for key: ArtworkKey) async throws { }
}
