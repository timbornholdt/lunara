import Foundation
import Testing
@testable import Lunara

@MainActor
struct LibraryRepoProtocolTests {
    @Test
    func libraryRefreshOutcome_totalItemCount_sumsAllEntityCounts() {
        let outcome = LibraryRefreshOutcome(
            reason: .userInitiated,
            refreshedAt: Date(timeIntervalSince1970: 1_705_000_000),
            albumCount: 12,
            trackCount: 121,
            artistCount: 6,
            collectionCount: 3
        )

        #expect(outcome.totalItemCount == 142)
    }

    @Test
    func fetchAlbums_readsSequentialPagesUntilShortPageReturned() async throws {
        let repo = ProtocolRepoMock()
        repo.albumsByPage[1] = [makeAlbum(id: "album-1"), makeAlbum(id: "album-2")]
        repo.albumsByPage[2] = [makeAlbum(id: "album-3")]

        let albums = try await repo.fetchAlbums(pageSize: 2)

        #expect(repo.albumPageRequests == [
            LibraryPage(number: 1, size: 2),
            LibraryPage(number: 2, size: 2)
        ])
        #expect(albums.map(\.plexID) == ["album-1", "album-2", "album-3"])
    }

    @Test
    func fetchAlbums_whenPagedReadFails_propagatesOriginalError() async {
        let repo = ProtocolRepoMock()
        repo.albumsByPage[1] = [makeAlbum(id: "album-1")]
        repo.albumsErrorByPage[2] = .databaseCorrupted

        do {
            _ = try await repo.fetchAlbums(pageSize: 1)
            Issue.record("Expected fetchAlbums to throw")
        } catch let error as LibraryError {
            #expect(error == .databaseCorrupted)
        } catch {
            Issue.record("Expected LibraryError, got: \(error)")
        }

        #expect(repo.albumPageRequests == [
            LibraryPage(number: 1, size: 1),
            LibraryPage(number: 2, size: 1)
        ])
    }

    @Test
    func queryServiceAPIs_captureSearchTermsAndLookupIDs() async throws {
        let repo = ProtocolRepoMock()
        let expectedTrack = Track(
            plexID: "track-1",
            albumID: "album-1",
            title: "Track 1",
            trackNumber: 1,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/track-1",
            thumbURL: nil
        )
        let expectedCollection = Collection(
            plexID: "collection-1",
            title: "Collection 1",
            thumbURL: nil,
            summary: nil,
            albumCount: 3,
            updatedAt: nil
        )
        repo.searchedAlbumsByQuery["miles"] = [makeAlbum(id: "album-1")]
        repo.queriedAlbumsByFilter[AlbumQueryFilter(textQuery: "miles")] = [makeAlbum(id: "album-2")]
        repo.searchedArtistsByQuery["coltrane"] = [Artist(
            plexID: "artist-1",
            name: "John Coltrane",
            sortName: "Coltrane, John",
            thumbURL: nil,
            genre: nil,
            summary: nil,
            albumCount: 10
        )]
        repo.searchedCollectionsByQuery["jazz"] = [expectedCollection]
        repo.trackByID[expectedTrack.plexID] = expectedTrack
        repo.collectionByID[expectedCollection.plexID] = expectedCollection

        let albums = try await repo.searchAlbums(query: "miles")
        let filteredAlbums = try await repo.queryAlbums(filter: AlbumQueryFilter(textQuery: "miles"))
        let artists = try await repo.searchArtists(query: "coltrane")
        let collections = try await repo.searchCollections(query: "jazz")
        let track = try await repo.track(id: "track-1")
        let collection = try await repo.collection(id: "collection-1")

        #expect(repo.searchAlbumQueries == ["miles"])
        #expect(repo.albumQueryFilters == [AlbumQueryFilter(textQuery: "miles")])
        #expect(repo.searchArtistQueries == ["coltrane"])
        #expect(repo.searchCollectionQueries == ["jazz"])
        #expect(repo.trackRequests == ["track-1"])
        #expect(repo.collectionRequests == ["collection-1"])
        #expect(albums.map(\.plexID) == ["album-1"])
        #expect(filteredAlbums.map(\.plexID) == ["album-2"])
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
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )
    }
}

@MainActor
private final class ProtocolRepoMock: LibraryRepoProtocol {
    var albumsByPage: [Int: [Album]] = [:]
    var albumsErrorByPage: [Int: LibraryError] = [:]
    var albumPageRequests: [LibraryPage] = []
    var searchedAlbumsByQuery: [String: [Album]] = [:]
    var queriedAlbumsByFilter: [AlbumQueryFilter: [Album]] = [:]
    var searchedArtistsByQuery: [String: [Artist]] = [:]
    var searchedCollectionsByQuery: [String: [Collection]] = [:]
    var trackByID: [String: Track] = [:]
    var collectionByID: [String: Collection] = [:]
    var searchAlbumQueries: [String] = []
    var albumQueryFilters: [AlbumQueryFilter] = []
    var searchArtistQueries: [String] = []
    var searchCollectionQueries: [String] = []
    var trackRequests: [String] = []
    var collectionRequests: [String] = []

    func albums(page: LibraryPage) async throws -> [Album] {
        albumPageRequests.append(page)
        if let error = albumsErrorByPage[page.number] {
            throw error
        }
        return albumsByPage[page.number] ?? []
    }

    func album(id: String) async throws -> Album? {
        nil
    }

    func searchAlbums(query: String) async throws -> [Album] {
        searchAlbumQueries.append(query)
        return searchedAlbumsByQuery[query] ?? []
    }

    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        albumQueryFilters.append(filter)
        return queriedAlbumsByFilter[filter] ?? []
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        []
    }

    func track(id: String) async throws -> Track? {
        trackRequests.append(id)
        return trackByID[id]
    }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }

    func collections() async throws -> [Collection] {
        []
    }

    func collection(id: String) async throws -> Collection? {
        collectionRequests.append(id)
        return collectionByID[id]
    }

    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }

    func searchCollections(query: String) async throws -> [Collection] {
        searchCollectionQueries.append(query)
        return searchedCollectionsByQuery[query] ?? []
    }

    func artists() async throws -> [Artist] {
        []
    }

    func artist(id: String) async throws -> Artist? {
        nil
    }

    func searchArtists(query: String) async throws -> [Artist] {
        searchArtistQueries.append(query)
        return searchedArtistsByQuery[query] ?? []
    }

    func artistAlbums(artistName: String) async throws -> [Album] { [] }

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

    func streamURL(for track: Track) async throws -> URL {
        throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
    }

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        nil
    }
}
