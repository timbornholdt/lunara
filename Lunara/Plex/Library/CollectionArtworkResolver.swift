import Foundation

struct CollectionArtworkResolver {
    let artworkBuilder: PlexArtworkURLBuilder

    func artworkPath(for collection: PlexCollection) -> String? {
        if let thumb = collection.thumb, !thumb.isEmpty {
            return thumb
        }
        if let art = collection.art, !art.isEmpty {
            return art
        }
        return nil
    }

    func artworkURL(for collection: PlexCollection) -> URL? {
        guard let path = artworkPath(for: collection) else { return nil }
        return artworkBuilder.makeTranscodedArtworkURL(artPath: path)
    }
}
