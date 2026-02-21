import Foundation
@testable import Lunara

final class MockOfflineStore: OfflineStoreProtocol, @unchecked Sendable {
    var localFileURLsByTrackID: [String: URL] = [:]
    var savedOfflineTracks: [OfflineTrack] = []
    var deletedAlbumIDs: [String] = []
    var storageBytesTotal: Int64 = 0
    var offlineTracksByAlbumID: [String: [OfflineTrack]] = [:]
    var offlineAlbumIDs: [String] = []

    func localFileURL(forTrackID trackID: String) async throws -> URL? {
        localFileURLsByTrackID[trackID]
    }

    func offlineStatus(forAlbum albumID: String, totalTrackCount: Int) async throws -> OfflineAlbumStatus {
        let tracks = offlineTracksByAlbumID[albumID] ?? []
        if tracks.isEmpty {
            return .notDownloaded
        } else if tracks.count >= totalTrackCount {
            return .downloaded
        } else {
            return .partiallyDownloaded(downloadedCount: tracks.count, totalCount: totalTrackCount)
        }
    }

    func saveOfflineTrack(_ offlineTrack: OfflineTrack) async throws {
        savedOfflineTracks.append(offlineTrack)
        offlineTracksByAlbumID[offlineTrack.albumID, default: []].append(offlineTrack)
    }

    func deleteOfflineTracks(forAlbum albumID: String) async throws {
        deletedAlbumIDs.append(albumID)
        offlineTracksByAlbumID.removeValue(forKey: albumID)
    }

    func totalOfflineStorageBytes() async throws -> Int64 {
        storageBytesTotal
    }

    func offlineTracks(forAlbum albumID: String) async throws -> [OfflineTrack] {
        offlineTracksByAlbumID[albumID] ?? []
    }

    func allOfflineAlbumIDs() async throws -> [String] {
        offlineAlbumIDs
    }

    // MARK: - Synced Collections

    var syncedCollections: Set<String> = []
    var albumCollectionMapping: [String: [String]] = [:]

    func syncedCollectionIDs() async throws -> [String] {
        Array(syncedCollections).sorted()
    }

    func addSyncedCollection(_ collectionID: String) async throws {
        syncedCollections.insert(collectionID)
    }

    func removeSyncedCollection(_ collectionID: String) async throws {
        syncedCollections.remove(collectionID)
    }

    func isSyncedCollection(_ collectionID: String) async throws -> Bool {
        syncedCollections.contains(collectionID)
    }

    func collectionIDs(forAlbum albumID: String) async throws -> [String] {
        albumCollectionMapping[albumID] ?? []
    }
}
