import Foundation

struct CollectionArtworkResolver {
    let artworkBuilder: PlexArtworkURLBuilder

    func artworkURL(for collection: PlexCollection) -> URL? {
        if let thumb = collection.thumb {
            return artworkBuilder.makeTranscodedArtworkURL(artPath: thumb)
        }
        if let art = collection.art {
            return artworkBuilder.makeTranscodedArtworkURL(artPath: art)
        }
        return nil
    }
}
