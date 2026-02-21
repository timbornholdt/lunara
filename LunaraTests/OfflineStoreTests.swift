import Foundation
import GRDB
import Testing
@testable import Lunara

@MainActor
struct OfflineStoreTests {
    // MARK: - localFileURL

    @Test
    func localFileURL_returnsNilWhenNoRecordExists() async throws {
        let subject = try makeSubject()
        let url = try await subject.store.localFileURL(forTrackID: "nonexistent")
        #expect(url == nil)
    }

    @Test
    func localFileURL_returnsFileURLWhenRecordAndFileExist() async throws {
        let subject = try makeSubject()
        let filename = "track1-abc.flac"
        let fileURL = subject.offlineDir.appendingPathComponent(filename)
        try Data("audio".utf8).write(to: fileURL)

        let track = OfflineTrack(trackID: "t1", albumID: "a1", filename: filename, downloadedAt: Date(), fileSizeBytes: 5)
        try await subject.store.saveOfflineTrack(track)

        let result = try await subject.store.localFileURL(forTrackID: "t1")
        #expect(result == fileURL)
    }

    @Test
    func localFileURL_deletesStaleRowWhenFileMissing() async throws {
        let subject = try makeSubject()
        let track = OfflineTrack(trackID: "t1", albumID: "a1", filename: "missing.flac", downloadedAt: Date(), fileSizeBytes: 100)
        try await subject.store.saveOfflineTrack(track)

        let result = try await subject.store.localFileURL(forTrackID: "t1")
        #expect(result == nil)

        // Verify row was deleted
        let status = try await subject.store.offlineStatus(forAlbum: "a1", totalTrackCount: 1)
        #expect(status == .notDownloaded)
    }

    // MARK: - offlineStatus

    @Test
    func offlineStatus_notDownloadedWhenNoTracks() async throws {
        let subject = try makeSubject()
        let status = try await subject.store.offlineStatus(forAlbum: "a1", totalTrackCount: 10)
        #expect(status == .notDownloaded)
    }

    @Test
    func offlineStatus_partiallyDownloadedWhenSomeTracksExist() async throws {
        let subject = try makeSubject()
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t1", albumID: "a1", filename: "f1.flac", downloadedAt: Date(), fileSizeBytes: 100)
        )

        let status = try await subject.store.offlineStatus(forAlbum: "a1", totalTrackCount: 3)
        #expect(status == .partiallyDownloaded(downloadedCount: 1, totalCount: 3))
    }

    @Test
    func offlineStatus_downloadedWhenAllTracksExist() async throws {
        let subject = try makeSubject()
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t1", albumID: "a1", filename: "f1.flac", downloadedAt: Date(), fileSizeBytes: 100)
        )
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t2", albumID: "a1", filename: "f2.flac", downloadedAt: Date(), fileSizeBytes: 200)
        )

        let status = try await subject.store.offlineStatus(forAlbum: "a1", totalTrackCount: 2)
        #expect(status == .downloaded)
    }

    // MARK: - saveOfflineTrack

    @Test
    func saveOfflineTrack_persistsAndRetrievable() async throws {
        let subject = try makeSubject()
        let now = Date(timeIntervalSince1970: 1000)
        let track = OfflineTrack(trackID: "t1", albumID: "a1", filename: "f1.flac", downloadedAt: now, fileSizeBytes: 500)
        try await subject.store.saveOfflineTrack(track)

        let tracks = try await subject.store.offlineTracks(forAlbum: "a1")
        #expect(tracks.count == 1)
        #expect(tracks[0].trackID == "t1")
        #expect(tracks[0].albumID == "a1")
        #expect(tracks[0].filename == "f1.flac")
        #expect(tracks[0].fileSizeBytes == 500)
    }

    // MARK: - deleteOfflineTracks

    @Test
    func deleteOfflineTracks_removesRowsAndFiles() async throws {
        let subject = try makeSubject()
        let filename = "track-del.flac"
        let fileURL = subject.offlineDir.appendingPathComponent(filename)
        try Data("audio".utf8).write(to: fileURL)

        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t1", albumID: "a1", filename: filename, downloadedAt: Date(), fileSizeBytes: 5)
        )

        try await subject.store.deleteOfflineTracks(forAlbum: "a1")

        let status = try await subject.store.offlineStatus(forAlbum: "a1", totalTrackCount: 1)
        #expect(status == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func deleteOfflineTracks_onlyDeletesTargetAlbum() async throws {
        let subject = try makeSubject()
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t1", albumID: "a1", filename: "f1.flac", downloadedAt: Date(), fileSizeBytes: 100)
        )
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t2", albumID: "a2", filename: "f2.flac", downloadedAt: Date(), fileSizeBytes: 200)
        )

        try await subject.store.deleteOfflineTracks(forAlbum: "a1")

        let status1 = try await subject.store.offlineStatus(forAlbum: "a1", totalTrackCount: 1)
        let status2 = try await subject.store.offlineStatus(forAlbum: "a2", totalTrackCount: 1)
        #expect(status1 == .notDownloaded)
        #expect(status2 == .downloaded)
    }

    // MARK: - totalOfflineStorageBytes

    @Test
    func totalOfflineStorageBytes_sumsAllRecords() async throws {
        let subject = try makeSubject()
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t1", albumID: "a1", filename: "f1.flac", downloadedAt: Date(), fileSizeBytes: 100)
        )
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t2", albumID: "a2", filename: "f2.flac", downloadedAt: Date(), fileSizeBytes: 250)
        )

        let total = try await subject.store.totalOfflineStorageBytes()
        #expect(total == 350)
    }

    @Test
    func totalOfflineStorageBytes_returnsZeroWhenEmpty() async throws {
        let subject = try makeSubject()
        let total = try await subject.store.totalOfflineStorageBytes()
        #expect(total == 0)
    }

    // MARK: - allOfflineAlbumIDs

    @Test
    func allOfflineAlbumIDs_returnsDistinctAlbumIDs() async throws {
        let subject = try makeSubject()
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t1", albumID: "a1", filename: "f1.flac", downloadedAt: Date(), fileSizeBytes: 100)
        )
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t2", albumID: "a1", filename: "f2.flac", downloadedAt: Date(), fileSizeBytes: 100)
        )
        try await subject.store.saveOfflineTrack(
            OfflineTrack(trackID: "t3", albumID: "a2", filename: "f3.flac", downloadedAt: Date(), fileSizeBytes: 100)
        )

        let albumIDs = try await subject.store.allOfflineAlbumIDs()
        #expect(albumIDs == ["a1", "a2"])
    }

    // MARK: - Synced Collections

    @Test
    func syncedCollectionIDs_returnsEmptyWhenNoneSynced() async throws {
        let subject = try makeSubject()
        let ids = try await subject.store.syncedCollectionIDs()
        #expect(ids.isEmpty)
    }

    @Test
    func addSyncedCollection_persistsAndRetrievable() async throws {
        let subject = try makeSubject()
        try await subject.store.addSyncedCollection("col-1")
        let ids = try await subject.store.syncedCollectionIDs()
        #expect(ids == ["col-1"])
    }

    @Test
    func removeSyncedCollection_removesMarker() async throws {
        let subject = try makeSubject()
        try await subject.store.addSyncedCollection("col-1")
        try await subject.store.removeSyncedCollection("col-1")
        let isSynced = try await subject.store.isSyncedCollection("col-1")
        #expect(!isSynced)
    }

    @Test
    func isSyncedCollection_returnsTrueWhenSynced() async throws {
        let subject = try makeSubject()
        try await subject.store.addSyncedCollection("col-1")
        let isSynced = try await subject.store.isSyncedCollection("col-1")
        #expect(isSynced)
    }

    @Test
    func isSyncedCollection_returnsFalseWhenNotSynced() async throws {
        let subject = try makeSubject()
        let isSynced = try await subject.store.isSyncedCollection("col-1")
        #expect(!isSynced)
    }

    // MARK: - Helpers

    private func makeSubject() throws -> (store: OfflineStore, offlineDir: URL) {
        let dbQueue = try DatabaseQueue(path: ":memory:")
        try LibraryStoreMigrations.migrator().migrate(dbQueue)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = OfflineStore(dbQueue: dbQueue, offlineDirectory: tempDir)
        return (store, tempDir)
    }
}
