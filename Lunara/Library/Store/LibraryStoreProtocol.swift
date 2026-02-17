import Foundation

/// One-based page descriptor used for paginated library reads.
struct LibraryPage: Equatable, Sendable {
    let number: Int
    let size: Int

    init(number: Int, size: Int) {
        self.number = max(1, number)
        self.size = max(1, size)
    }

    var offset: Int {
        (number - 1) * size
    }
}

/// A full library snapshot fetched from Plex and ready to persist atomically.
struct LibrarySnapshot: Equatable, Sendable {
    let albums: [Album]
    let tracks: [Track]
    let artists: [Artist]
    let collections: [Collection]

    var isEmpty: Bool {
        albums.isEmpty && tracks.isEmpty && artists.isEmpty && collections.isEmpty
    }

    func tracks(forAlbumID albumID: String) -> [Track] {
        tracks
            .filter { $0.albumID == albumID }
            .sorted { $0.trackNumber < $1.trackNumber }
    }
}

enum ArtworkOwnerType: String, Equatable, Sendable {
    case album
    case artist
    case collection
}

enum ArtworkVariant: String, Equatable, Sendable {
    case thumbnail
    case full
}

struct ArtworkKey: Equatable, Hashable, Sendable {
    let ownerID: String
    let ownerType: ArtworkOwnerType
    let variant: ArtworkVariant
}

/// Storage contract for the Library domain.
/// Implementations own schema/migrations and map to Shared models.
protocol LibraryStoreProtocol: AnyObject {
    func fetchAlbums(page: LibraryPage) async throws -> [Album]
    func fetchAlbum(id: String) async throws -> Album?

    func fetchTracks(forAlbum albumID: String) async throws -> [Track]

    func fetchArtists() async throws -> [Artist]
    func fetchArtist(id: String) async throws -> Artist?

    func fetchCollections() async throws -> [Collection]

    func replaceLibrary(with snapshot: LibrarySnapshot, refreshedAt: Date) async throws
    func lastRefreshDate() async throws -> Date?

    func artworkPath(for key: ArtworkKey) async throws -> String?
    func setArtworkPath(_ path: String, for key: ArtworkKey) async throws
    func deleteArtworkPath(for key: ArtworkKey) async throws
}
