import Foundation

struct ArtworkRequestBuilder {
    let baseURL: URL
    let token: String

    func albumRequest(for album: PlexAlbum, size: ArtworkSize) -> ArtworkRequest? {
        let resolver = AlbumArtworkResolver(artworkBuilder: PlexArtworkURLBuilder(
            baseURL: baseURL,
            token: token,
            maxSize: size.maxPixelSize
        ))
        guard let path = resolver.artworkPath(for: album) else { return nil }
        let url = resolver.artworkURL(for: album)
        guard let url else { return nil }
        let key = ArtworkCacheKey(ratingKey: album.ratingKey, artworkPath: path, size: size)
        return ArtworkRequest(key: key, url: url)
    }

    func collectionRequest(for collection: PlexCollection, size: ArtworkSize) -> ArtworkRequest? {
        let resolver = CollectionArtworkResolver(artworkBuilder: PlexArtworkURLBuilder(
            baseURL: baseURL,
            token: token,
            maxSize: size.maxPixelSize
        ))
        guard let path = resolver.artworkPath(for: collection) else { return nil }
        let url = resolver.artworkURL(for: collection)
        guard let url else { return nil }
        let key = ArtworkCacheKey(ratingKey: collection.ratingKey, artworkPath: path, size: size)
        return ArtworkRequest(key: key, url: url)
    }
}
