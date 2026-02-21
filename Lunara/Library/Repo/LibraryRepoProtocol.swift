import Foundation

enum LibraryRefreshReason: Equatable, Sendable {
    case appLaunch
    case userInitiated
}

struct LibraryRefreshOutcome: Equatable, Sendable {
    let reason: LibraryRefreshReason
    let refreshedAt: Date
    let albumCount: Int
    let trackCount: Int
    let artistCount: Int
    let collectionCount: Int

    var totalItemCount: Int {
        albumCount + trackCount + artistCount + collectionCount
    }
}

struct AlbumDetailRefreshOutcome: Equatable, Sendable {
    let album: Album?
    let tracks: [Track]
}

@MainActor
protocol LibraryRepoProtocol: AnyObject {
    /// Reads a single cached album page.
    /// Implementations should return quickly from local storage.
    func albums(page: LibraryPage) async throws -> [Album]
    func album(id: String) async throws -> Album?
    /// Queries cached albums by `album.title` and `album.artistName`.
    /// - Sorting guarantee: results are fully sorted by source ordering (`artistName`, then `title`).
    func searchAlbums(query: String) async throws -> [Album]
    /// Queries the full cached album catalog with flexible relational filtering.
    /// - Sorting guarantee: results are fully sorted by source ordering (`artistName`, then `title`, then `plexID`).
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album]

    func tracks(forAlbum albumID: String) async throws -> [Track]
    func track(id: String) async throws -> Track?
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome
    func collections() async throws -> [Collection]
    func collection(id: String) async throws -> Collection?
    /// Fetches albums belonging to a collection, querying the remote API for membership.
    func collectionAlbums(collectionID: String) async throws -> [Album]
    /// Queries cached artists by name and sort name.
    /// - Sorting guarantee: results are fully sorted by source ordering (`sortName`, then `name`).
    func searchArtists(query: String) async throws -> [Artist]
    /// Queries cached collections by title.
    /// - Sorting guarantee: results are fully sorted by source ordering (`title`).
    func searchCollections(query: String) async throws -> [Collection]
    func artists() async throws -> [Artist]
    func artist(id: String) async throws -> Artist?

    /// Reads all persisted playlists from cache, ordered by title.
    /// Playlists are populated during `refreshLibrary`; this method does not trigger a remote fetch.
    func playlists() async throws -> [LibraryPlaylistSnapshot]

    /// Reads ordered items for one playlist from cache, preserving Plex item order including duplicate track IDs.
    /// Items are populated during `refreshLibrary`; this method does not trigger a remote fetch.
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot]

    /// Performs a remote refresh and persists it atomically.
    /// Implementations must preserve existing cache when this throws.
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome
    func lastRefreshDate() async throws -> Date?

    func streamURL(for track: Track) async throws -> URL
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL?
}

extension LibraryRepoProtocol {
    /// Convenience helper for callers that still need a full in-memory list.
    /// Fetches paginated data and preserves thrown errors from any page read.
    func fetchAlbums(pageSize: Int = 200) async throws -> [Album] {
        var allAlbums: [Album] = []
        var pageNumber = 1
        let sanitizedPageSize = max(1, pageSize)

        while true {
            let page = LibraryPage(number: pageNumber, size: sanitizedPageSize)
            let batch = try await albums(page: page)
            allAlbums.append(contentsOf: batch)

            if batch.count < sanitizedPageSize {
                break
            }

            pageNumber += 1
        }

        return allAlbums
    }

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        guard let rawValue,
              let sourceURL = URL(string: rawValue),
              sourceURL.scheme != nil else {
            return nil
        }

        return sourceURL
    }
}

extension PlexAPIClient: LibraryRepoProtocol {
    func albums(page: LibraryPage) async throws -> [Album] {
        let allAlbums = try await fetchAlbums()
        guard page.offset < allAlbums.count else {
            return []
        }

        let endIndex = min(page.offset + page.size, allAlbums.count)
        return Array(allAlbums[page.offset..<endIndex])
    }

    func album(id: String) async throws -> Album? {
        try await fetchAlbum(id: id)
    }

    func searchAlbums(query: String) async throws -> [Album] {
        throw LibraryError.operationFailed(reason: "Album search is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] {
        throw LibraryError.operationFailed(reason: "Album filtering is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        try await fetchTracks(forAlbum: albumID)
    }

    func track(id: String) async throws -> Track? {
        try await fetchTrack(id: id)
    }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        let album = try await fetchAlbum(id: albumID)
        let tracks = try await fetchTracks(forAlbum: albumID)
        return AlbumDetailRefreshOutcome(album: album, tracks: tracks)
    }

    func collections() async throws -> [Collection] {
        throw LibraryError.operationFailed(reason: "Collections fetch is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func collection(id: String) async throws -> Collection? {
        throw LibraryError.operationFailed(reason: "Collection lookup is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func collectionAlbums(collectionID: String) async throws -> [Album] {
        throw LibraryError.operationFailed(reason: "Collection albums is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func searchCollections(query: String) async throws -> [Collection] {
        throw LibraryError.operationFailed(reason: "Collection search is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func artists() async throws -> [Artist] {
        throw LibraryError.operationFailed(reason: "Artists fetch is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func artist(id: String) async throws -> Artist? {
        throw LibraryError.operationFailed(reason: "Artist fetch is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func searchArtists(query: String) async throws -> [Artist] {
        throw LibraryError.operationFailed(reason: "Artist search is not implemented on PlexAPIClient-backed LibraryRepo yet.")
    }

    func playlists() async throws -> [LibraryPlaylistSnapshot] {
        throw LibraryError.operationFailed(reason: "Playlist reads are not implemented on PlexAPIClient-backed LibraryRepo.")
    }

    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] {
        throw LibraryError.operationFailed(reason: "Playlist item reads are not implemented on PlexAPIClient-backed LibraryRepo.")
    }

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        throw LibraryError.operationFailed(reason: "Library refresh orchestration is not implemented yet.")
    }

    func lastRefreshDate() async throws -> Date? {
        nil
    }

    func streamURL(for track: Track) async throws -> URL {
        try await streamURL(forTrack: track)
    }

}
