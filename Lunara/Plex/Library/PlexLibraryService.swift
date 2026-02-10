import Foundation

struct PlexLibraryService: PlexLibraryServicing {
    let httpClient: PlexHTTPClienting
    let requestBuilder: PlexLibraryRequestBuilder
    let paginator: PlexPaginator

    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        let request = requestBuilder.makeLibrarySectionsRequest()
        let response = try await httpClient.send(request, decode: PlexDirectoryResponse<PlexLibrarySection>.self)
        return response.mediaContainer.items
    }

    func fetchAlbums(sectionId: String) async throws -> [PlexAlbum] {
        try await paginator.fetchAll { offset in
            let request = requestBuilder.makeAlbumsRequest(sectionId: sectionId, offset: offset, size: paginator.pageSize)
            let response = try await httpClient.send(request, decode: PlexResponse<PlexAlbum>.self)
            let container = response.mediaContainer
            let total = container.totalSize ?? container.size
            return PlexPage(
                items: container.items,
                offset: container.offset ?? offset,
                size: container.size,
                totalSize: total
            )
        }
    }

    func fetchTracks(albumRatingKey: String) async throws -> [PlexTrack] {
        let request = requestBuilder.makeAlbumTracksRequest(albumRatingKey: albumRatingKey)
        let response = try await httpClient.send(request, decode: PlexResponse<PlexTrack>.self)
        return response.mediaContainer.items
    }

    func fetchAlbumDetail(albumRatingKey: String) async throws -> PlexAlbum? {
        let request = requestBuilder.makeAlbumDetailRequest(albumRatingKey: albumRatingKey)
        let response = try await httpClient.send(request, decode: PlexResponse<PlexAlbum>.self)
        return response.mediaContainer.items.first
    }

    func fetchCollections(sectionId: String) async throws -> [PlexCollection] {
        try await paginator.fetchAll { offset in
            let request = requestBuilder.makeCollectionsRequest(sectionId: sectionId, offset: offset, size: paginator.pageSize)
            let response = try await httpClient.send(request, decode: PlexResponse<PlexCollection>.self)
            let container = response.mediaContainer
            let total = container.totalSize ?? container.size
            return PlexPage(
                items: container.items,
                offset: container.offset ?? offset,
                size: container.size,
                totalSize: total
            )
        }
    }

    func fetchAlbumsInCollection(sectionId: String, collectionKey: String) async throws -> [PlexAlbum] {
        try await paginator.fetchAll { offset in
            let request = requestBuilder.makeCollectionItemsRequest(collectionKey: collectionKey, offset: offset, size: paginator.pageSize)
            let response = try await httpClient.send(request, decode: PlexResponse<PlexAlbum>.self)
            let container = response.mediaContainer
            let total = container.totalSize ?? container.size
            return PlexPage(
                items: container.items,
                offset: container.offset ?? offset,
                size: container.size,
                totalSize: total
            )
        }
    }

    func fetchArtists(sectionId: String) async throws -> [PlexArtist] {
        try await paginator.fetchAll { offset in
            let request = requestBuilder.makeArtistsRequest(sectionId: sectionId, offset: offset, size: paginator.pageSize)
            let response = try await httpClient.send(request, decode: PlexResponse<PlexArtist>.self)
            let container = response.mediaContainer
            let total = container.totalSize ?? container.size
            return PlexPage(
                items: container.items,
                offset: container.offset ?? offset,
                size: container.size,
                totalSize: total
            )
        }
    }

    func fetchArtistDetail(artistRatingKey: String) async throws -> PlexArtist? {
        let request = requestBuilder.makeArtistDetailRequest(artistRatingKey: artistRatingKey)
        let response = try await httpClient.send(request, decode: PlexResponse<PlexArtist>.self)
        return response.mediaContainer.items.first
    }

    func fetchArtistAlbums(artistRatingKey: String) async throws -> [PlexAlbum] {
        try await paginator.fetchAll { offset in
            let request = requestBuilder.makeArtistAlbumsRequest(
                artistRatingKey: artistRatingKey,
                offset: offset,
                size: paginator.pageSize
            )
            let response = try await httpClient.send(request, decode: PlexResponse<PlexAlbum>.self)
            let container = response.mediaContainer
            let total = container.totalSize ?? container.size
            return PlexPage(
                items: container.items,
                offset: container.offset ?? offset,
                size: container.size,
                totalSize: total
            )
        }
    }

    func fetchArtistTracks(artistRatingKey: String) async throws -> [PlexTrack] {
        try await paginator.fetchAll { offset in
            let request = requestBuilder.makeArtistTracksRequest(
                artistRatingKey: artistRatingKey,
                offset: offset,
                size: paginator.pageSize
            )
            let response = try await httpClient.send(request, decode: PlexResponse<PlexTrack>.self)
            let container = response.mediaContainer
            let total = container.totalSize ?? container.size
            return PlexPage(
                items: container.items,
                offset: container.offset ?? offset,
                size: container.size,
                totalSize: total
            )
        }
    }
}
