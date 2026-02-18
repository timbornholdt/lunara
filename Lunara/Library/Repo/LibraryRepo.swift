import Foundation

/// Network contract consumed by LibraryRepo.
/// Kept protocol-based so repository behavior can be unit-tested with mocks.
protocol LibraryRemoteDataSource: AnyObject {
    func fetchAlbums() async throws -> [Album]
    func fetchTracks(forAlbum albumID: String) async throws -> [Track]
    func streamURL(forTrack track: Track) async throws -> URL
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL?
}

extension PlexAPIClient: LibraryRemoteDataSource { }

@MainActor
final class LibraryRepo: LibraryRepoProtocol {
    private struct DedupeGroup {
        var canonicalAlbum: Album
        var tracksByID: [String: Track]
    }

    private struct DedupeResult {
        let albums: [Album]
        let tracks: [Track]
    }

    private let remote: LibraryRemoteDataSource
    private let store: LibraryStoreProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
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
        try await store.fetchAlbum(id: id)
    }

    func tracks(forAlbum albumID: String) async throws -> [Track] {
        let cachedTracks = try await store.fetchTracks(forAlbum: albumID)
        if !cachedTracks.isEmpty {
            return cachedTracks
        }

        do {
            return try await remote.fetchTracks(forAlbum: albumID)
        } catch let error as LibraryError {
            throw error
        } catch {
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

    private func dedupeLibrary(albums: [Album], tracks: [Track]) -> DedupeResult {
        var groups: [String: DedupeGroup] = [:]
        var albumIDsByGroupKey: [String: [String]] = [:]

        for album in albums {
            let key = dedupeKey(for: album)
            if let existingGroup = groups[key] {
                let canonicalAlbum = canonicalAlbum(between: existingGroup.canonicalAlbum, and: album)
                groups[key]?.canonicalAlbum = canonicalAlbum
                albumIDsByGroupKey[key, default: []].append(album.plexID)
                continue
            }

            groups[key] = DedupeGroup(canonicalAlbum: album, tracksByID: [:])
            albumIDsByGroupKey[key] = [album.plexID]
        }

        var albumIDToGroupKey: [String: String] = [:]
        for (groupKey, albumIDs) in albumIDsByGroupKey {
            for albumID in albumIDs {
                albumIDToGroupKey[albumID] = groupKey
            }
        }

        for track in tracks {
            guard let groupKey = albumIDToGroupKey[track.albumID] else {
                continue
            }
            guard let group = groups[groupKey] else {
                continue
            }

            let canonicalAlbumID = group.canonicalAlbum.plexID
            let canonicalTrack = Track(
                plexID: track.plexID,
                albumID: canonicalAlbumID,
                title: track.title,
                trackNumber: track.trackNumber,
                duration: track.duration,
                artistName: track.artistName,
                key: track.key,
                thumbURL: track.thumbURL
            )
            groups[groupKey]?.tracksByID[track.plexID] = canonicalTrack
        }

        let sortedGroupKeys = groups.keys.sorted()
        var dedupedAlbums: [Album] = []
        var dedupedTracks: [Track] = []

        dedupedAlbums.reserveCapacity(groups.count)
        dedupedTracks.reserveCapacity(tracks.count)

        for groupKey in sortedGroupKeys {
            guard let group = groups[groupKey] else {
                continue
            }

            let mergedTracks = group.tracksByID.values.sorted {
                if $0.trackNumber != $1.trackNumber {
                    return $0.trackNumber < $1.trackNumber
                }
                if $0.title != $1.title {
                    return $0.title < $1.title
                }
                return $0.plexID < $1.plexID
            }

            let mergedDuration = mergedTracks.reduce(0) { $0 + max(0, $1.duration) }
            let mergedAlbum = Album(
                plexID: group.canonicalAlbum.plexID,
                title: group.canonicalAlbum.title,
                artistName: group.canonicalAlbum.artistName,
                year: group.canonicalAlbum.year,
                thumbURL: group.canonicalAlbum.thumbURL,
                genre: group.canonicalAlbum.genre,
                rating: group.canonicalAlbum.rating,
                addedAt: group.canonicalAlbum.addedAt,
                trackCount: max(group.canonicalAlbum.trackCount, mergedTracks.count),
                duration: max(group.canonicalAlbum.duration, mergedDuration)
            )

            dedupedAlbums.append(mergedAlbum)
            dedupedTracks.append(contentsOf: mergedTracks)
        }

        return DedupeResult(albums: dedupedAlbums, tracks: dedupedTracks)
    }

    private func dedupeKey(for album: Album) -> String {
        "\(normalizeForDedupe(album.artistName))|\(normalizeForDedupe(album.title))|\(album.year?.description ?? "")"
    }

    private func normalizeForDedupe(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func canonicalAlbum(between lhs: Album, and rhs: Album) -> Album {
        if lhs.plexID <= rhs.plexID {
            return mergeAlbumMetadata(primary: lhs, fallback: rhs)
        }
        return mergeAlbumMetadata(primary: rhs, fallback: lhs)
    }

    private func mergeAlbumMetadata(primary: Album, fallback: Album) -> Album {
        Album(
            plexID: primary.plexID,
            title: primary.title,
            artistName: primary.artistName,
            year: primary.year ?? fallback.year,
            thumbURL: primary.thumbURL ?? fallback.thumbURL,
            genre: primary.genre ?? fallback.genre,
            rating: primary.rating ?? fallback.rating,
            addedAt: primary.addedAt ?? fallback.addedAt,
            trackCount: max(primary.trackCount, fallback.trackCount),
            duration: max(primary.duration, fallback.duration)
        )
    }

    private func preloadThumbnailArtwork(for albums: [Album]) async {
        for album in albums {
            do {
                let sourceURL = try await remote.authenticatedArtworkURL(for: album.thumbURL)
                _ = try await artworkPipeline.fetchThumbnail(
                    for: album.plexID,
                    ownerKind: .album,
                    sourceURL: sourceURL
                )
            } catch {
                // Artwork warmup is best-effort so metadata refresh remains available when image fetch fails.
                continue
            }
        }
    }
}
