import Foundation

struct PlexLibraryService {
    let httpClient: PlexHTTPClient
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
}
