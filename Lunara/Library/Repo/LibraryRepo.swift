import Foundation

/// Network contract consumed by LibraryRepo.
/// Kept protocol-based so repository behavior can be unit-tested with mocks.
protocol LibraryRemoteDataSource: AnyObject {
    func fetchAlbums() async throws -> [Album]
    func fetchAlbum(id albumID: String) async throws -> Album?
    func fetchTracks(forAlbum albumID: String) async throws -> [Track]
    func streamURL(forTrack track: Track) async throws -> URL
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL?
}

extension PlexAPIClient: LibraryRemoteDataSource { }

@MainActor
final class LibraryRepo: LibraryRepoProtocol {
    struct DedupeGroup {
        var canonicalAlbum: Album
        var tracksByID: [String: Track]
    }

    struct DedupeResult {
        let albums: [Album]
        let tracks: [Track]
    }

    let remote: LibraryRemoteDataSource
    let store: LibraryStoreProtocol
    let artworkPipeline: ArtworkPipelineProtocol
    let nowProvider: () -> Date

    init(
        remote: LibraryRemoteDataSource,
        store: LibraryStoreProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.remote = remote
        self.store = store
        self.artworkPipeline = artworkPipeline
        self.nowProvider = nowProvider
    }

    func albums(page: LibraryPage) async throws -> [Album] {
        try await store.fetchAlbums(page: page)
    }

    func album(id: String) async throws -> Album? {
        let cachedAlbum = try await store.fetchAlbum(id: id)
        guard let cachedAlbum else {
            return try await remote.fetchAlbum(id: id)
        }

        if cachedAlbum.review != nil,
           !cachedAlbum.genres.isEmpty,
           !cachedAlbum.styles.isEmpty,
           !cachedAlbum.moods.isEmpty {
            return cachedAlbum
        }

        guard let remoteAlbum = try await remote.fetchAlbum(id: id) else {
            return cachedAlbum
        }

        return mergeAlbumMetadata(primary: remoteAlbum, fallback: cachedAlbum)
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        let cachedTracks = try await store.fetchTracks(forAlbum: albumID)

        do {
            let remoteTracks = try await remote.fetchTracks(forAlbum: albumID)
            if !remoteTracks.isEmpty {
                return remoteTracks
            }
            return cachedTracks
        } catch let error as LibraryError {
            if !cachedTracks.isEmpty {
                return cachedTracks
            }
            throw error
        } catch {
            if !cachedTracks.isEmpty {
                return cachedTracks
            }
            throw LibraryError.operationFailed(reason: "Track fetch failed: \(error.localizedDescription)")
        }
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

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        do {
            return try await remote.authenticatedArtworkURL(for: rawValue)
        } catch let error as LibraryError {
            throw error
        } catch {
            throw LibraryError.operationFailed(reason: "Artwork URL resolution failed: \(error.localizedDescription)")
        }
    }
}
