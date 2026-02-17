import Foundation

/// Network contract consumed by LibraryRepo.
/// Kept protocol-based so repository behavior can be unit-tested with mocks.
protocol LibraryRemoteDataSource: AnyObject {
    func fetchAlbums() async throws -> [Album]
    func fetchTracks(forAlbum albumID: String) async throws -> [Track]
    func streamURL(forTrack track: Track) async throws -> URL
}

extension PlexAPIClient: LibraryRemoteDataSource { }

@MainActor
final class LibraryRepo: LibraryRepoProtocol {
    private let remote: LibraryRemoteDataSource
    private let store: LibraryStoreProtocol
    private let nowProvider: () -> Date

    init(
        remote: LibraryRemoteDataSource,
        store: LibraryStoreProtocol,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.remote = remote
        self.store = store
        self.nowProvider = nowProvider
    }

    func albums(page: LibraryPage) async throws -> [Album] {
        try await store.fetchAlbums(page: page)
    }

    func album(id: String) async throws -> Album? {
        try await store.fetchAlbum(id: id)
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        try await store.fetchTracks(forAlbum: albumID)
    }

    func collections() async throws -> [Collection] {
        try await store.fetchCollections()
    }

    func artists() async throws -> [Artist] {
        try await store.fetchArtists()
    }

    func artist(id: String) async throws -> Artist? {
        try await store.fetchArtist(id: id)
    }

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        let refreshedAt = nowProvider()

        do {
            let albums = try await remote.fetchAlbums()

            var tracks: [Track] = []
            tracks.reserveCapacity(albums.reduce(0) { $0 + max(0, $1.trackCount) })

            for album in albums {
                let albumTracks = try await remote.fetchTracks(forAlbum: album.plexID)
                tracks.append(contentsOf: albumTracks)
            }

            // Artist/collection endpoints are not exposed by PlexAPIClient yet.
            // Preserve cached values so refresh updates album/track data without erasing other cache slices.
            let cachedArtists = try await store.fetchArtists()
            let cachedCollections = try await store.fetchCollections()
            let snapshot = LibrarySnapshot(
                albums: albums,
                tracks: tracks,
                artists: cachedArtists,
                collections: cachedCollections
            )

            try await store.replaceLibrary(with: snapshot, refreshedAt: refreshedAt)

            return LibraryRefreshOutcome(
                reason: reason,
                refreshedAt: refreshedAt,
                albumCount: albums.count,
                trackCount: tracks.count,
                artistCount: cachedArtists.count,
                collectionCount: cachedCollections.count
            )
        } catch let error as LibraryError {
            throw error
        } catch {
            throw LibraryError.operationFailed(reason: "Library refresh failed: \(error.localizedDescription)")
        }
    }

    func lastRefreshDate() async throws -> Date? {
        try await store.lastRefreshDate()
    }

    func streamURL(for track: Track) async throws -> URL {
        do {
            return try await remote.streamURL(forTrack: track)
        } catch let error as LibraryError {
            throw error
        } catch {
            throw LibraryError.operationFailed(reason: "Stream URL resolution failed: \(error.localizedDescription)")
        }
    }
}
