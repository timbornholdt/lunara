import Foundation

/// Network contract consumed by LibraryRepo.
/// Kept protocol-based so repository behavior can be unit-tested with mocks.
protocol LibraryRemoteDataSource: AnyObject {
    func fetchAlbums() async throws -> [Album]
    func fetchAlbum(id albumID: String) async throws -> Album?
    func fetchTracks(forAlbum albumID: String) async throws -> [Track]
    func fetchTrack(id trackID: String) async throws -> Track?
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
        if let cachedAlbum {
            return cachedAlbum
        }

        guard let remoteAlbum = try await remote.fetchAlbum(id: id) else {
            return nil
        }

        try await store.upsertAlbum(remoteAlbum)
        return remoteAlbum
    }

    func searchAlbums(query: String) async throws -> [Album] {
        try await store.searchAlbums(query: query)
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        let cachedTracks = try await store.fetchTracks(forAlbum: albumID)
        if !cachedTracks.isEmpty {
            return cachedTracks
        }

        let remoteTracks = try await remote.fetchTracks(forAlbum: albumID)
        try await store.replaceTracks(remoteTracks, forAlbum: albumID)
        return remoteTracks
    }

    func track(id: String) async throws -> Track? {
        if let cachedTrack = try await store.track(id: id) {
            return cachedTrack
        }

        guard let remoteTrack = try await remote.fetchTrack(id: id) else {
            return nil
        }

        try await store.replaceTracks([remoteTrack], forAlbum: remoteTrack.albumID)
        return remoteTrack
    }

    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        async let remoteAlbumTask = remote.fetchAlbum(id: albumID)
        async let remoteTracksTask = remote.fetchTracks(forAlbum: albumID)

        let remoteAlbum = try await remoteAlbumTask
        let remoteTracks = try await remoteTracksTask

        if let remoteAlbum {
            try await store.upsertAlbum(remoteAlbum)
        }
        try await store.replaceTracks(remoteTracks, forAlbum: albumID)

        return AlbumDetailRefreshOutcome(album: remoteAlbum, tracks: remoteTracks)
    }

    func collections() async throws -> [Collection] {
        try await store.fetchCollections()
    }

    func collection(id: String) async throws -> Collection? {
        try await store.collection(id: id)
    }

    func searchCollections(query: String) async throws -> [Collection] {
        try await store.searchCollections(query: query)
    }

    func artists() async throws -> [Artist] {
        try await store.fetchArtists()
    }

    func artist(id: String) async throws -> Artist? {
        try await store.fetchArtist(id: id)
    }

    func searchArtists(query: String) async throws -> [Artist] {
        try await store.searchArtists(query: query)
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
