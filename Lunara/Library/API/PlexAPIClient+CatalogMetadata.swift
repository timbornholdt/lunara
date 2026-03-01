import Foundation

extension PlexAPIClient {
    func fetchArtists() async throws -> [Artist] {
        let request = try await buildRequest(
            path: "/library/sections/4/all",
            queryItems: [URLQueryItem(name: "type", value: "8")],
            requiresAuth: true
        )
        let (data, _) = try await executeLoggedRequest(request, operation: "fetchArtists")
        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)

        let directories = container.directories ?? []
        var artists: [Artist] = []
        artists.reserveCapacity(directories.count)

        for directory in directories where directory.type == "artist" {
            guard let artistID = directory.ratingKey, !artistID.isEmpty else {
                throw LibraryError.invalidResponse
            }
            artists.append(
                Artist(
                    plexID: artistID,
                    name: directory.title,
                    sortName: directory.titleSort,
                    thumbURL: directory.thumb,
                    genre: directory.genre,
                    summary: directory.summary,
                    albumCount: directory.childCount ?? directory.leafCount ?? 0
                )
            )
        }

        return artists.sorted { lhs, rhs in
            if lhs.effectiveSortName != rhs.effectiveSortName {
                return lhs.effectiveSortName < rhs.effectiveSortName
            }
            return lhs.plexID < rhs.plexID
        }
    }

    func fetchCollections() async throws -> [Collection] {
        let request = try await buildRequest(
            path: "/library/sections/4/all",
            queryItems: [URLQueryItem(name: "type", value: "18")],
            requiresAuth: true
        )
        let (data, _) = try await executeLoggedRequest(request, operation: "fetchCollections")
        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)

        if let directories = container.directories, !directories.isEmpty {
            return try parseCollections(from: directories)
        }

        let metadata = container.metadata ?? []
        return try parseCollections(from: metadata)
    }

    func fetchPlaylists() async throws -> [LibraryRemotePlaylist] {
        let request = try await buildRequest(path: "/playlists/all", requiresAuth: true)
        let (data, _) = try await executeLoggedRequest(request, operation: "fetchPlaylists")
        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        let metadata = container.metadata ?? []

        var playlists: [LibraryRemotePlaylist] = []
        playlists.reserveCapacity(metadata.count)

        for entry in metadata where entry.type == "playlist" {
            let updatedAt = (entry.updatedAt ?? entry.addedAt).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let count = entry.leafCount ?? entry.trackCount ?? 0
            playlists.append(
                LibraryRemotePlaylist(
                    plexID: entry.ratingKey,
                    title: entry.title,
                    trackCount: count,
                    updatedAt: updatedAt,
                    thumb: entry.thumb ?? entry.composite
                )
            )
        }

        return playlists.sorted { lhs, rhs in
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.plexID < rhs.plexID
        }
    }

    func fetchPlaylistItems(playlistID: String) async throws -> [LibraryRemotePlaylistItem] {
        let request = try await buildRequest(path: "/playlists/\(playlistID)/items", requiresAuth: true)
        let (data, _) = try await executeLoggedRequest(request, operation: "fetchPlaylistItems[\(playlistID)]")
        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        let metadata = container.metadata ?? []

        var items: [LibraryRemotePlaylistItem] = []
        items.reserveCapacity(metadata.count)

        for (index, entry) in metadata.enumerated() where entry.type == "track" {
            let itemID = entry.playlistItemID.map(String.init)
            items.append(LibraryRemotePlaylistItem(trackID: entry.ratingKey, position: index, playlistItemID: itemID))
        }
        return items
    }

    /// Fetch albums filtered by a tag (genre, style, or mood) from the Plex API.
    func fetchAlbumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] {
        let filterParam: String
        switch kind {
        case .genre: filterParam = "genre"
        case .style: filterParam = "style"
        case .mood: filterParam = "mood"
        }

        let request = try await buildRequest(
            path: "/library/sections/4/all",
            queryItems: [
                URLQueryItem(name: "type", value: "9"),
                URLQueryItem(name: filterParam, value: value)
            ],
            requiresAuth: true
        )

        let (data, _) = try await executeLoggedRequest(request, operation: "fetchAlbumsByTag[\(kind.rawValue)=\(value)]")
        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        guard let directories = container.directories else {
            return []
        }

        var albums: [Album] = []
        albums.reserveCapacity(directories.count)

        for directory in directories where directory.type == "album" {
            guard let albumID = directory.ratingKey, !albumID.isEmpty else {
                continue
            }

            let addedAtDate = directory.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let durationSeconds = directory.duration.map { TimeInterval($0) / 1000.0 } ?? 0.0
            let resolvedGenres = dedupedTags(directory.genres + [directory.genre].compactMap { $0 })
            let releaseDate = directory.originallyAvailableAt.flatMap { Self.parseReleaseDateString($0) }

            albums.append(Album(
                plexID: albumID,
                title: directory.title,
                artistName: directory.parentTitle ?? "Unknown Artist",
                year: directory.year,
                releaseDate: releaseDate,
                thumbURL: directory.thumb,
                genre: resolvedGenres.first,
                rating: directory.rating.map { Int($0) },
                addedAt: addedAtDate,
                trackCount: directory.leafCount ?? 0,
                duration: durationSeconds,
                review: directory.summary,
                genres: resolvedGenres,
                styles: dedupedTags(directory.styles),
                moods: dedupedTags(directory.moods)
            ))
        }

        return albums
    }

    /// Fetch album IDs that belong to a specific collection.
    func fetchCollectionAlbumIDs(collectionID: String) async throws -> [String] {
        let request = try await buildRequest(
            path: "/library/collections/\(collectionID)/children",
            requiresAuth: true
        )
        let (data, _) = try await executeLoggedRequest(request, operation: "fetchCollectionAlbumIDs[\(collectionID)]")
        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)

        var albumIDs: [String] = []

        if let directories = container.directories {
            for directory in directories where directory.type == "album" {
                if let ratingKey = directory.ratingKey, !ratingKey.isEmpty {
                    albumIDs.append(ratingKey)
                }
            }
        }

        if let metadata = container.metadata {
            for entry in metadata where entry.type == "album" {
                if !entry.ratingKey.isEmpty {
                    albumIDs.append(entry.ratingKey)
                }
            }
        }

        return albumIDs
    }

    private func parseCollections(from directories: [PlexDirectory]) throws -> [Collection] {
        var collections: [Collection] = []
        collections.reserveCapacity(directories.count)

        for directory in directories where directory.type == "collection" {
            guard let collectionID = directory.ratingKey, !collectionID.isEmpty else {
                throw LibraryError.invalidResponse
            }
            let updatedAt = directory.updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            collections.append(
                Collection(
                    plexID: collectionID,
                    title: directory.title,
                    thumbURL: directory.thumb,
                    summary: directory.summary,
                    albumCount: directory.childCount ?? directory.leafCount ?? 0,
                    updatedAt: updatedAt
                )
            )
        }

        return collections.sorted { lhs, rhs in
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.plexID < rhs.plexID
        }
    }

    private func parseCollections(from metadata: [PlexMetadata]) throws -> [Collection] {
        var collections: [Collection] = []
        collections.reserveCapacity(metadata.count)

        for entry in metadata where entry.type == "collection" {
            let updatedAt = (entry.updatedAt ?? entry.addedAt).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            collections.append(
                Collection(
                    plexID: entry.ratingKey,
                    title: entry.title,
                    thumbURL: entry.thumb,
                    summary: entry.summary,
                    albumCount: entry.albumCount ?? entry.leafCount ?? entry.trackCount ?? 0,
                    updatedAt: updatedAt
                )
            )
        }

        return collections.sorted { lhs, rhs in
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.plexID < rhs.plexID
        }
    }
}
