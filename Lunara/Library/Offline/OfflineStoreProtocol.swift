import Foundation

protocol OfflineStoreProtocol: AnyObject, Sendable {
    /// Returns the local file URL for a downloaded track, or nil if not available offline.
    /// If the DB row exists but the file is missing on disk, deletes the stale row and returns nil.
    func localFileURL(forTrackID trackID: String) async throws -> URL?

    /// Returns the offline status for an album given its total track count.
    func offlineStatus(forAlbum albumID: String, totalTrackCount: Int) async throws -> OfflineAlbumStatus

    /// Persists metadata for a downloaded track.
    func saveOfflineTrack(_ offlineTrack: OfflineTrack) async throws

    /// Deletes all offline track records (and their files) for the given album.
    func deleteOfflineTracks(forAlbum albumID: String) async throws

    /// Returns the total bytes used by all offline tracks.
    func totalOfflineStorageBytes() async throws -> Int64

    /// Returns all offline tracks for a given album.
    func offlineTracks(forAlbum albumID: String) async throws -> [OfflineTrack]

    /// Returns all unique album IDs that have at least one offline track.
    func allOfflineAlbumIDs() async throws -> [String]

    // MARK: - Synced Collections

    /// Returns all collection IDs marked for sync.
    func syncedCollectionIDs() async throws -> [String]

    /// Marks a collection for automatic sync.
    func addSyncedCollection(_ collectionID: String) async throws

    /// Removes a collection from automatic sync.
    func removeSyncedCollection(_ collectionID: String) async throws

    /// Returns whether a collection is marked for sync.
    func isSyncedCollection(_ collectionID: String) async throws -> Bool

    /// Returns all collection IDs that contain the given album (via album_collections junction table).
    func collectionIDs(forAlbum albumID: String) async throws -> [String]
}
