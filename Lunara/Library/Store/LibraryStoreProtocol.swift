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

/// Logical identifier for a single incremental sync execution.
struct LibrarySyncRun: Equatable, Sendable {
    let id: String
    let startedAt: Date

    init(id: String = UUID().uuidString, startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
    }
}

/// Persisted checkpoint metadata used to resume or diagnose sync behavior.
struct LibrarySyncCheckpoint: Equatable, Sendable {
    let key: String
    let value: String
    let updatedAt: Date
}

/// IDs pruned at the end of a reconciliation run.
struct LibrarySyncPruneResult: Equatable, Sendable {
    let prunedAlbumIDs: [String]
    let prunedTrackIDs: [String]

    var isEmpty: Bool {
        prunedAlbumIDs.isEmpty && prunedTrackIDs.isEmpty
    }

    static let empty = LibrarySyncPruneResult(prunedAlbumIDs: [], prunedTrackIDs: [])
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

    /// Starts a new incremental synchronization run.
    /// - Transaction guarantee: this call must commit atomically and leave previous refresh data untouched if it fails.
    func beginIncrementalSync(startedAt: Date) async throws -> LibrarySyncRun

    /// Upserts album rows for the provided sync run.
    /// - Transaction guarantee: all provided albums are written atomically or no album rows are changed.
    func upsertAlbums(_ albums: [Album], in run: LibrarySyncRun) async throws

    /// Upserts track rows for the provided sync run.
    /// - Transaction guarantee: all provided tracks are written atomically or no track rows are changed.
    func upsertTracks(_ tracks: [Track], in run: LibrarySyncRun) async throws

    /// Marks album rows as observed in the active sync run.
    /// - Transaction guarantee: all album IDs in this call are marked together or none are marked.
    func markAlbumsSeen(_ albumIDs: [String], in run: LibrarySyncRun) async throws

    /// Marks track rows as observed in the active sync run.
    /// - Transaction guarantee: all track IDs in this call are marked together or none are marked.
    func markTracksSeen(_ trackIDs: [String], in run: LibrarySyncRun) async throws

    /// Prunes rows not seen during the provided sync run.
    /// - Transaction guarantee: album/track pruning must complete atomically so callers never observe half-pruned state.
    func pruneRowsNotSeen(in run: LibrarySyncRun) async throws -> LibrarySyncPruneResult

    /// Persists a sync checkpoint value for diagnostics/recovery.
    /// - Transaction guarantee: checkpoint updates are atomic per key.
    func setSyncCheckpoint(_ checkpoint: LibrarySyncCheckpoint, in run: LibrarySyncRun?) async throws
    func syncCheckpoint(forKey key: String) async throws -> LibrarySyncCheckpoint?

    /// Finalizes an incremental sync run and records the successful refresh timestamp.
    /// - Transaction guarantee: sync completion and refresh timestamp write must commit atomically.
    func completeIncrementalSync(_ run: LibrarySyncRun, refreshedAt: Date) async throws

    func artworkPath(for key: ArtworkKey) async throws -> String?
    func setArtworkPath(_ path: String, for key: ArtworkKey) async throws
    func deleteArtworkPath(for key: ArtworkKey) async throws
}
