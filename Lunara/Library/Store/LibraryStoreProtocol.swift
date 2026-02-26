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

enum LibraryTagKind: String, CaseIterable, Equatable, Sendable {
    case genre
    case style
    case mood
}

struct LibraryPlaylistSnapshot: Equatable, Sendable {
    let plexID: String
    let title: String
    let trackCount: Int
    let updatedAt: Date?
}

struct LibraryPlaylistItemSnapshot: Equatable, Sendable {
    let trackID: String
    let position: Int
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

struct AlbumQueryFilter: Equatable, Hashable, Sendable {
    let textQuery: String?
    let yearRange: ClosedRange<Int>?
    let genreTags: [String]
    let styleTags: [String]
    let moodTags: [String]
    let artistIDs: [String]
    let collectionIDs: [String]

    init(
        textQuery: String? = nil,
        yearRange: ClosedRange<Int>? = nil,
        genreTags: [String] = [],
        styleTags: [String] = [],
        moodTags: [String] = [],
        artistIDs: [String] = [],
        collectionIDs: [String] = []
    ) {
        self.textQuery = textQuery
        self.yearRange = yearRange
        self.genreTags = genreTags
        self.styleTags = styleTags
        self.moodTags = moodTags
        self.artistIDs = artistIDs
        self.collectionIDs = collectionIDs
    }

    static let all = AlbumQueryFilter()
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
    func upsertAlbum(_ album: Album) async throws

    func fetchTracks(forAlbum albumID: String) async throws -> [Track]
    func track(id: String) async throws -> Track?
    func replaceTracks(_ tracks: [Track], forAlbum albumID: String) async throws

    func fetchArtists() async throws -> [Artist]
    func fetchArtist(id: String) async throws -> Artist?
    func fetchAlbumsByArtistName(_ artistName: String) async throws -> [Album]

    func fetchCollections() async throws -> [Collection]
    func collection(id: String) async throws -> Collection?

    /// Queries the full cached album catalog by album title and artist name.
    /// - Sorting guarantee: results are fully sorted by source ordering (`artistName`, then `title`).
    func searchAlbums(query: String) async throws -> [Album]

    /// Queries the full cached album catalog with flexible relational filtering.
    ///
    /// Filter semantics:
    /// - `textQuery`: case/diacritic-insensitive substring match across album title and artist name.
    /// - `yearRange`: inclusive bounds; albums with unknown year are excluded when bounds are present.
    /// - `genreTags`/`styleTags`/`moodTags`: ALL semantics within each kind (album must match every provided tag in that kind).
    /// - `artistIDs`/`collectionIDs`: ALL semantics within each list (album must match every provided relation ID).
    ///
    /// - Sorting guarantee: deterministic source ordering (`artistName`, then `title`, then `plexID`).
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album]

    /// Queries the full cached artist catalog by artist name and sort name.
    /// - Sorting guarantee: results are fully sorted by source ordering (`sortName`, then `name`).
    func searchArtists(query: String) async throws -> [Artist]

    /// Queries the full cached collection catalog by collection title.
    /// - Sorting guarantee: results are fully sorted by source ordering (`title`).
    func searchCollections(query: String) async throws -> [Collection]

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

    /// Reconciles artist rows for the provided sync run using Plex artist IDs as canonical keys.
    /// - Transaction guarantee: all artist rows in this call are upserted atomically or no artist rows are changed.
    func replaceArtists(_ artists: [Artist], in run: LibrarySyncRun) async throws

    /// Reconciles collection rows for the provided sync run using Plex collection IDs as canonical keys.
    /// - Transaction guarantee: all collection rows in this call are upserted atomically or no collection rows are changed.
    func replaceCollections(_ collections: [Collection], in run: LibrarySyncRun) async throws

    /// Upserts album↔collection join rows for the provided sync run.
    /// - Parameter albumCollectionIDs: mapping of album plexID → array of collection plexIDs.
    /// - Transaction guarantee: all join rows are written atomically or none are changed.
    func upsertAlbumCollections(_ albumCollectionIDs: [String: [String]], in run: LibrarySyncRun) async throws

    /// Reconciles playlist rows for the provided sync run using Plex playlist IDs as canonical keys.
    /// - Transaction guarantee: all playlist rows in this call are upserted atomically or no playlist rows are changed.
    func upsertPlaylists(_ playlists: [LibraryPlaylistSnapshot], in run: LibrarySyncRun) async throws

    /// Reconciles ordered playlist item rows for one playlist in the provided sync run.
    /// - Transaction guarantee: all playlist items for `playlistID` in this call are written atomically or no playlist items are changed.
    func upsertPlaylistItems(
        _ items: [LibraryPlaylistItemSnapshot],
        playlistID: String,
        in run: LibrarySyncRun
    ) async throws

    /// Reads all persisted playlists ordered by title.
    func fetchPlaylists() async throws -> [LibraryPlaylistSnapshot]

    /// Reads ordered items for one playlist.
    /// - Sorting guarantee: results are returned in ascending `position` order preserving Plex item order including duplicates.
    func fetchPlaylistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot]

    /// Marks album rows as observed in the active sync run.
    /// - Transaction guarantee: all album IDs in this call are marked together or none are marked.
    func markAlbumsSeen(_ albumIDs: [String], in run: LibrarySyncRun) async throws

    /// Marks track rows as observed in the active sync run.
    /// - Transaction guarantee: all track IDs in this call are marked together or none are marked.
    func markTracksSeen(_ trackIDs: [String], in run: LibrarySyncRun) async throws

    /// Marks all tracks whose album was seen in the current sync run as seen, preventing pruning of cached tracks.
    /// - Transaction guarantee: all matching track rows are updated atomically.
    func markTracksWithValidAlbumsSeen(in run: LibrarySyncRun) async throws

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

    /// Returns all distinct tag names for the given kind, ordered alphabetically.
    func fetchTags(kind: LibraryTagKind) async throws -> [String]

    func artworkPath(for key: ArtworkKey) async throws -> String?
    func setArtworkPath(_ path: String, for key: ArtworkKey) async throws
    func deleteArtworkPath(for key: ArtworkKey) async throws
}
