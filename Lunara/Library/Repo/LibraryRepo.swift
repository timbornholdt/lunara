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
    private let store: LibraryStoreProtocol
    let artworkPipeline: ArtworkPipelineProtocol
    private let nowProvider: () -> Date

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

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        let refreshedAt = nowProvider()

        do {
            let remoteAlbums = try await remote.fetchAlbums()
            var cachedTracks: [Track] = []
            for album in remoteAlbums {
                let albumTracks = try await store.fetchTracks(forAlbum: album.plexID)
                if !albumTracks.isEmpty {
                    cachedTracks.append(contentsOf: albumTracks)
                }
            }

            let dedupedLibrary = dedupeLibrary(albums: remoteAlbums, tracks: cachedTracks)

            // Artist/collection endpoints are not exposed by PlexAPIClient yet.
            // Preserve cached values so refresh updates album/track data without erasing other cache slices.
            let cachedArtists = try await store.fetchArtists()
            let cachedCollections = try await store.fetchCollections()
            let snapshot = LibrarySnapshot(
                albums: dedupedLibrary.albums,
                tracks: dedupedLibrary.tracks,
                artists: cachedArtists,
                collections: cachedCollections
            )

            try await store.replaceLibrary(with: snapshot, refreshedAt: refreshedAt)
            let dedupedAlbums = dedupedLibrary.albums
            Task { [weak self] in
                guard let self else {
                    return
                }
                await self.preloadThumbnailArtwork(for: dedupedAlbums)
            }

            return LibraryRefreshOutcome(
                reason: reason,
                refreshedAt: refreshedAt,
                albumCount: dedupedLibrary.albums.count,
                trackCount: cachedTracks.count,
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
