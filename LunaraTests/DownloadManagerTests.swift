import Foundation
import Testing
@testable import Lunara

@MainActor
struct DownloadManagerTests {

    @Test
    func downloadState_defaultsToIdle() {
        let subject = makeSubject()
        #expect(subject.manager.downloadState(forAlbum: "a1") == .idle)
    }

    @Test
    func downloadAlbum_downloadsTracksSequentiallyAndCompletes() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        subject.library.streamURLByTrackID["t1"] = URL(string: "https://example.com/t1.flac")!

        await subject.manager.downloadAlbum(album, tracks: [track])

        #expect(subject.manager.downloadState(forAlbum: "a1") == .complete)
        #expect(subject.offlineStore.savedOfflineTracks.count == 1)
        #expect(subject.offlineStore.savedOfflineTracks[0].trackID == "t1")
    }

    @Test
    func downloadAlbum_skipsAlreadyDownloadedTracks() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")

        // Mark track as already downloaded
        let tempFile = subject.offlineDir.appendingPathComponent("existing.flac")
        try Data("audio".utf8).write(to: tempFile)
        subject.offlineStore.localFileURLsByTrackID["t1"] = tempFile

        subject.library.streamURLByTrackID["t1"] = URL(string: "https://example.com/t1.flac")!

        await subject.manager.downloadAlbum(album, tracks: [track])

        #expect(subject.manager.downloadState(forAlbum: "a1") == .complete)
        // Should not have saved a new track (skipped)
        #expect(subject.offlineStore.savedOfflineTracks.isEmpty)
    }

    @Test
    func downloadAlbum_abortsOnStorageCapReached() async {
        let subject = makeSubject()
        subject.manager.storageLimitBytes = 100
        subject.offlineStore.storageBytesTotal = 200 // Over limit

        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        subject.library.streamURLByTrackID["t1"] = URL(string: "https://example.com/t1.flac")!

        await subject.manager.downloadAlbum(album, tracks: [track])

        #expect(subject.manager.downloadState(forAlbum: "a1") == .failed("Storage limit reached"))
        #expect(subject.offlineStore.deletedAlbumIDs.contains("a1"))
    }

    @Test
    func cancelDownload_cleansUpPartialDownload() async throws {
        let subject = makeSubject()
        // Just verify cancel sets state to idle and cleans up
        subject.manager.cancelDownload(forAlbum: "a1")
        #expect(subject.manager.downloadState(forAlbum: "a1") == .idle)
    }

    @Test
    func removeDownload_deletesOfflineTracksAndResetsState() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        subject.library.streamURLByTrackID["t1"] = URL(string: "https://example.com/t1.flac")!

        await subject.manager.downloadAlbum(album, tracks: [track])
        #expect(subject.manager.downloadState(forAlbum: "a1") == .complete)

        try await subject.manager.removeDownload(forAlbum: "a1")
        #expect(subject.manager.downloadState(forAlbum: "a1") == .idle)
        #expect(subject.offlineStore.deletedAlbumIDs.contains("a1"))
    }

    @Test
    func downloadAlbum_networkFailureCleansUp() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        subject.library.streamURLError = LibraryError.plexUnreachable

        await subject.manager.downloadAlbum(album, tracks: [track])

        #expect(subject.manager.downloadState(forAlbum: "a1") == .failed("Download failed"))
        #expect(subject.offlineStore.deletedAlbumIDs.contains("a1"))
    }

    @Test
    func syncCollection_marksSyncedAndDownloadsAlbums() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        subject.library.tracksByAlbumID["a1"] = [track]
        subject.library.streamURLByTrackID["t1"] = URL(string: "https://example.com/t1.flac")!

        await subject.manager.syncCollection("col-1", albums: [album], library: subject.library)

        let isSynced = try? await subject.offlineStore.isSyncedCollection("col-1")
        #expect(isSynced == true)
        #expect(subject.offlineStore.savedOfflineTracks.count == 1)
    }

    @Test
    func unsyncCollection_removesSyncMarkerAndOrphanedDownloads() async {
        let subject = makeSubject()
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        subject.library.tracksByAlbumID["a1"] = [track]
        subject.library.streamURLByTrackID["t1"] = URL(string: "https://example.com/t1.flac")!
        subject.library.collectionAlbumsByID["col-1"] = [album]
        subject.offlineStore.albumCollectionMapping["a1"] = ["col-1"]

        await subject.manager.syncCollection("col-1", albums: [album], library: subject.library)
        await subject.manager.unsyncCollection("col-1", library: subject.library)

        let isSynced = try? await subject.offlineStore.isSyncedCollection("col-1")
        #expect(isSynced == false)
        #expect(subject.offlineStore.deletedAlbumIDs.contains("a1"))
    }

    // MARK: - Offline availability change signal (Lunara-uww.3.6)

    @Test
    func downloadAlbumCompletion_firesOfflineAvailabilityChanged() async throws {
        let subject = makeSubject()
        var received: [Set<String>] = []
        subject.manager.onOfflineAvailabilityChanged = { received.append($0) }
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        subject.library.streamURLByTrackID["t1"] = URL(string: "https://example.com/t1.flac")!

        await subject.manager.downloadAlbum(album, tracks: [track])

        #expect(subject.manager.downloadState(forAlbum: "a1") == .complete)
        #expect(received.contains(["a1"]))
    }

    @Test
    func removeDownload_firesOfflineAvailabilityChanged() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        subject.library.streamURLByTrackID["t1"] = URL(string: "https://example.com/t1.flac")!
        await subject.manager.downloadAlbum(album, tracks: [track])

        // Only watch the removal, not the prior completion.
        var received: [Set<String>] = []
        subject.manager.onOfflineAvailabilityChanged = { received.append($0) }

        try await subject.manager.removeDownload(forAlbum: "a1")

        #expect(received.contains(["a1"]))
    }

    @Test
    func cancelDownload_firesOfflineAvailabilityChangedAfterDeletion() async throws {
        let subject = makeSubject()
        var received: [Set<String>] = []
        subject.manager.onOfflineAvailabilityChanged = { received.append($0) }

        subject.manager.cancelDownload(forAlbum: "a1")
        // cancelDownload deletes offline files in a detached task; the signal fires
        // after that deletion completes.
        await waitUntil { received.contains(["a1"]) }

        #expect(received.contains(["a1"]))
        #expect(subject.offlineStore.deletedAlbumIDs.contains("a1"))
    }

    @Test
    func failedDownloadCleanup_firesOfflineAvailabilityChanged() async throws {
        let subject = makeSubject()
        var received: [Set<String>] = []
        subject.manager.onOfflineAvailabilityChanged = { received.append($0) }
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        // Force a failure mid-download → cleanupFailedDownload deletes saved files.
        subject.library.streamURLError = LibraryError.plexUnreachable

        await subject.manager.downloadAlbum(album, tracks: [track])

        #expect(subject.manager.downloadState(forAlbum: "a1") == .failed("Download failed"))
        #expect(received.contains(["a1"]))
    }

    // MARK: - Helpers

    // MARK: - Orphaned files + atomicity (Lunara-uww.3.7)

    /// A file written to disk whose metadata save then fails must be deleted
    /// immediately — cleanup only knows about store-backed files, so a file
    /// without a row would otherwise leak forever.
    @Test
    func saveFailure_removesWrittenFileFromDisk() async throws {
        let subject = makeSubject()
        let album = makeAlbum(id: "a1")
        let track = makeTrack(id: "t1", albumID: "a1")
        let source = subject.offlineDir.appendingPathComponent("source.mp3")
        try Data("audio".utf8).write(to: source)
        subject.library.streamURLByTrackID["t1"] = source
        subject.offlineStore.saveOfflineTrackError = LibraryError.operationFailed(reason: "db full")

        await subject.manager.downloadAlbum(album, tracks: [track])

        #expect(subject.manager.downloadState(forAlbum: "a1") == .failed("Download failed"))
        // Only the source fixture remains: the downloaded copy was removed when
        // its save failed.
        let remaining = try FileManager.default.contentsOfDirectory(atPath: subject.offlineDir.path)
        #expect(remaining == ["source.mp3"])
    }

    /// Files in the offline directory with no store row (write interrupted before
    /// the metadata save — crash, cancellation) are swept; store-backed files stay.
    @Test
    func removeOrphanedFiles_deletesFilesWithoutStoreRows() async throws {
        let subject = makeSubject()
        let known = subject.offlineDir.appendingPathComponent("known.mp3")
        try Data("k".utf8).write(to: known)
        subject.offlineStore.offlineAlbumIDs = ["a1"]
        subject.offlineStore.offlineTracksByAlbumID["a1"] = [
            OfflineTrack(trackID: "t1", albumID: "a1", filename: "known.mp3", downloadedAt: Date(), fileSizeBytes: 1)
        ]
        let orphan = subject.offlineDir.appendingPathComponent("orphan.mp3")
        try Data("o".utf8).write(to: orphan)

        await subject.manager.removeOrphanedFiles()

        #expect(FileManager.default.fileExists(atPath: known.path))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    private func waitUntil(
        iterations: Int = 50,
        condition: @escaping () -> Bool
    ) async {
        for _ in 0..<iterations {
            if condition() { return }
            await Task.yield()
        }
    }

    private func makeSubject() -> (
        manager: DownloadManager,
        offlineStore: MockOfflineStore,
        library: DownloadManagerLibraryMock,
        offlineDir: URL
    ) {
        let offlineStore = MockOfflineStore()
        let library = DownloadManagerLibraryMock()
        let offlineDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: offlineDir, withIntermediateDirectories: true)
        let manager = DownloadManager(
            offlineStore: offlineStore,
            library: library,
            offlineDirectory: offlineDir
        )
        manager.wifiOnly = false // Disable Wi-Fi check for tests
        return (manager, offlineStore, library, offlineDir)
    }

    private func makeAlbum(id: String) -> Album {
        Album(
            plexID: id,
            title: "Album \(id)",
            artistName: "Artist",
            year: nil,
            thumbURL: nil,
            genre: nil,
            rating: nil,
            addedAt: nil,
            trackCount: 0,
            duration: 0
        )
    }

    private func makeTrack(id: String, albumID: String = "a1") -> Track {
        Track(
            plexID: id,
            albumID: albumID,
            title: "Track \(id)",
            trackNumber: 1,
            duration: 180,
            artistName: "Artist",
            key: "/library/metadata/\(id)",
            thumbURL: nil
        )
    }
}

/// Minimal library mock for DownloadManager tests — only needs streamURL.
@MainActor
private final class DownloadManagerLibraryMock: LibraryRepoProtocol {
    var streamURLByTrackID: [String: URL] = [:]
    var streamURLError: LibraryError?
    var tracksByAlbumID: [String: [Track]] = [:]
    var collectionAlbumsByID: [String: [Album]] = [:]

    func streamURL(for track: Track) async throws -> URL {
        if let error = streamURLError { throw error }
        guard let url = streamURLByTrackID[track.plexID] else {
            throw LibraryError.resourceNotFound(type: "track", id: track.plexID)
        }
        return url
    }

    // Unused stubs
    func albums(page: LibraryPage) async throws -> [Album] { [] }
    func album(id: String) async throws -> Album? { nil }
    func searchAlbums(query: String) async throws -> [Album] { [] }
    func queryAlbums(filter: AlbumQueryFilter) async throws -> [Album] { [] }
    func tracks(forAlbum albumID: String) async throws -> [Track] { tracksByAlbumID[albumID] ?? [] }
    func track(id: String) async throws -> Track? { nil }
    func refreshAlbumDetail(albumID: String) async throws -> AlbumDetailRefreshOutcome {
        AlbumDetailRefreshOutcome(album: nil, tracks: [])
    }
    func collections() async throws -> [Collection] { [] }
    func collection(id: String) async throws -> Collection? { nil }
    func collectionAlbums(collectionID: String) async throws -> [Album] { collectionAlbumsByID[collectionID] ?? [] }
    func searchCollections(query: String) async throws -> [Collection] { [] }
    func artists() async throws -> [Artist] { [] }
    func artist(id: String) async throws -> Artist? { nil }
    func searchArtists(query: String) async throws -> [Artist] { [] }
    func artistAlbums(artistName: String) async throws -> [Album] { [] }
    func playlists() async throws -> [LibraryPlaylistSnapshot] { [] }
    func playlistItems(playlistID: String) async throws -> [LibraryPlaylistItemSnapshot] { [] }
    func searchPlaylists(query: String) async throws -> [LibraryPlaylistSnapshot] { [] }
    func addToPlaylist(playlistID: String, ratingKey: String) async throws { }
    func removeFromPlaylist(playlistID: String, playlistItemID: String) async throws { }
    func availableTags(kind: LibraryTagKind) async throws -> [String] { [] }
    func albumsByTag(kind: LibraryTagKind, value: String) async throws -> [Album] { [] }
    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        LibraryRefreshOutcome(reason: reason, refreshedAt: Date(), albumCount: 0, trackCount: 0, artistCount: 0, collectionCount: 0)
    }
    func lastRefreshDate() async throws -> Date? { nil }
    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? { nil }
}
