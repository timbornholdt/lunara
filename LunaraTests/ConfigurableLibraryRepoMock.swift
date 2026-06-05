import Foundation
@testable import Lunara

/// Reusable, configurable `LibraryRepoProtocol` double for view-model tests.
///
/// Set the `…ByID` dictionaries (or the list properties) to control what the repo returns.
/// Everything defaults to empty/nil so a test only configures what it exercises.
/// `authenticatedArtworkURL`, `fetchLoudnessLevels`, and `fetchAlbums` come from the protocol's
/// default extension and need no override here.
@MainActor
final class ConfigurableLibraryRepoMock: LibraryRepoProtocol {
    // Configurable backing data.
    var albumsByID: [String: Album] = [:]
    var tracksByID: [String: Track] = [:]
    var artistsByID: [String: Artist] = [:]
    var collectionsByID: [String: Collection] = [:]
    var allAlbums: [Album] = []
    var allArtists: [Artist] = []
    var allCollections: [Collection] = []
    var tracksByAlbumID: [String: [Track]] = [:]
    var albumsByArtistName: [String: [Album]] = [:]
    var playlistSnapshots: [LibraryPlaylistSnapshot] = []
    var playlistItemsByID: [String: [LibraryPlaylistItemSnapshot]] = [:]
    var lastRefresh: Date?
    /// URL returned by `streamURL(for:)`; defaults to a throwaway file URL.
    var streamURLToReturn = URL(fileURLWithPath: "/tmp/stream.m4a")

    func albums(page: LibraryPage) async throws -> [Album] {
        guard page.offset < allAlbums.count else { return [] }
        let end = min(page.offset + page.size, allAlbums.count)
        return Array(allAlbums[page.offset..<end])
    }

    func album(id: String) async throws -> Album? { albumsByID[id] }
    func searchAlbums(query: String) async throws -> [Album] { allAlbums }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { allAlbums }
    func tracks(forAlbum albumID: String) async throws -> [Track] { tracksByAlbumID[albumID] ?? [] }
    func track(id: String) async throws -> Track? { tracksByID[id] }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: albumsByID[albumID], tracks: tracksByAlbumID[albumID] ?? [])
    }

    func collections() async throws -> [Collection] { allCollections }
    func collection(id: String) async throws -> Collection? { collectionsByID[id] }
    func collectionAlbums(collectionID: String) async throws -> [Album] { [] }
    func searchArtists(query: String) async throws -> [Artist] { allArtists }
    func searchCollections(query: String) async throws -> [Collection] { allCollections }
    func artists() async throws -> [Artist] { allArtists }
    func artist(id: String) async throws -> Artist? { artistsByID[id] }
    func artistAlbums(artistName: String) async throws -> [Album] { albumsByArtistName[artistName] ?? [] }
    func playlists() async throws -> [LibraryPlaylistSnapshot] { playlistSnapshots }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] {
        playlistItemsByID[playlistID] ?? []
    }
    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { playlistSnapshots }
    func addToPlaylist(playlistID: String, ratingKey: String) async throws {}
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws {}
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(
            reason: reason,
            refreshedAt: lastRefresh ?? Date(timeIntervalSince1970: 0),
            albumCount: allAlbums.count,
            trackCount: tracksByID.count,
            artistCount: allArtists.count,
            collectionCount: allCollections.count
        )
    }

    func lastRefreshDate() async throws -> Date? { lastRefresh }
    func streamURL(for track: Track) async throws -> URL { streamURLToReturn }
}
