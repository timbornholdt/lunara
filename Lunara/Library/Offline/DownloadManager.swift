import Foundation
import Network
import os

@MainActor
@Observable
final class DownloadManager: DownloadManagerProtocol {
    private let offlineStore: OfflineStoreProtocol
    private let library: LibraryRepoProtocol
    private let session: URLSession
    private let offlineDirectory: URL
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "DownloadManager")

    var storageLimitBytes: Int64 = 128 * 1024 * 1024 * 1024 // 128 GB default
    var wifiOnly: Bool = true

    private(set) var albumStates: [String: AlbumDownloadState] = [:]
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(
        offlineStore: OfflineStoreProtocol,
        library: LibraryRepoProtocol,
        session: URLSession = .shared,
        offlineDirectory: URL
    ) {
        self.offlineStore = offlineStore
        self.library = library
        self.session = session
        self.offlineDirectory = offlineDirectory
    }

    func downloadState(forAlbum albumID: String) -> AlbumDownloadState {
        albumStates[albumID] ?? .idle
    }

    func resolvedDownloadState(forAlbum albumID: String, totalTrackCount: Int) async -> AlbumDownloadState {
        let inMemory = albumStates[albumID]
        if let inMemory, inMemory != .idle {
            return inMemory
        }
        guard totalTrackCount > 0 else { return .idle }
        do {
            let status = try await offlineStore.offlineStatus(forAlbum: albumID, totalTrackCount: totalTrackCount)
            switch status {
            case .notDownloaded:
                return .idle
            case .downloaded:
                return .complete
            case .partiallyDownloaded(let downloaded, let total):
                return .downloading(completedTracks: downloaded, totalTracks: total)
            }
        } catch {
            return .idle
        }
    }

    func downloadAlbum(_ album: Album, tracks: [Track]) async {
        let albumID = album.plexID
        logger.info("downloadAlbum called for '\(albumID, privacy: .public)' with \(tracks.count) tracks")
        guard activeTasks[albumID] == nil else {
            logger.info("downloadAlbum: already active for '\(albumID, privacy: .public)' — skipping")
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performDownload(album: album, tracks: tracks)
        }
        activeTasks[albumID] = task
        await task.value
        activeTasks.removeValue(forKey: albumID)
    }

    func cancelDownload(forAlbum albumID: String) {
        activeTasks[albumID]?.cancel()
        activeTasks.removeValue(forKey: albumID)
        albumStates[albumID] = .idle

        Task { [weak self] in
            guard let self else { return }
            try? await self.offlineStore.deleteOfflineTracks(forAlbum: albumID)
        }
    }

    func removeDownload(forAlbum albumID: String) async throws {
        cancelDownload(forAlbum: albumID)
        try await offlineStore.deleteOfflineTracks(forAlbum: albumID)
        albumStates[albumID] = .idle
    }

    func syncCollection(_ collectionID: String, albums: [Album], library: LibraryRepoProtocol) async {
        logger.info("syncCollection: syncing collection '\(collectionID, privacy: .public)' with \(albums.count) albums")

        // Mark as synced
        try? await offlineStore.addSyncedCollection(collectionID)

        // Get currently downloaded album IDs
        let downloadedAlbumIDs = Set((try? await offlineStore.allOfflineAlbumIDs()) ?? [])
        let currentAlbumIDs = Set(albums.map(\.plexID))

        // Download new albums
        for album in albums {
            guard !downloadedAlbumIDs.contains(album.plexID) else { continue }
            do {
                let tracks = try await library.tracks(forAlbum: album.plexID)
                guard !tracks.isEmpty else { continue }
                await downloadAlbum(album, tracks: tracks)
            } catch {
                logger.warning("syncCollection: failed to load tracks for album '\(album.plexID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        // Remove stale albums (downloaded but no longer in collection)
        let staleAlbumIDs = downloadedAlbumIDs.subtracting(currentAlbumIDs)
        for albumID in staleAlbumIDs {
            // Check if album belongs to another synced collection
            let albumCollections = (try? await offlineStore.collectionIDs(forAlbum: albumID)) ?? []
            let syncedIDs = Set((try? await offlineStore.syncedCollectionIDs()) ?? [])
            let otherSyncedCollections = Set(albumCollections).intersection(syncedIDs).subtracting([collectionID])
            if otherSyncedCollections.isEmpty {
                try? await removeDownload(forAlbum: albumID)
                logger.info("syncCollection: removed stale album '\(albumID, privacy: .public)'")
            }
        }
    }

    func unsyncCollection(_ collectionID: String, library: LibraryRepoProtocol) async {
        logger.info("unsyncCollection: unsyncing collection '\(collectionID, privacy: .public)'")

        // Get albums in this collection before removing the sync marker
        let albumIDs: [String]
        do {
            let albums = try await library.collectionAlbums(collectionID: collectionID)
            albumIDs = albums.map(\.plexID)
        } catch {
            albumIDs = []
        }

        // Remove sync marker
        try? await offlineStore.removeSyncedCollection(collectionID)

        // Remove orphaned downloads
        let syncedIDs = Set((try? await offlineStore.syncedCollectionIDs()) ?? [])
        for albumID in albumIDs {
            let albumCollections = (try? await offlineStore.collectionIDs(forAlbum: albumID)) ?? []
            let stillSynced = Set(albumCollections).intersection(syncedIDs)
            if stillSynced.isEmpty {
                try? await removeDownload(forAlbum: albumID)
                logger.info("unsyncCollection: removed orphaned album '\(albumID, privacy: .public)'")
            }
        }
    }

    // MARK: - Private

    private func performDownload(album: Album, tracks: [Track]) async {
        let albumID = album.plexID
        let totalTracks = tracks.count
        albumStates[albumID] = .downloading(completedTracks: 0, totalTracks: totalTracks)

        for (index, track) in tracks.enumerated() {
            guard !Task.isCancelled else {
                await cleanupFailedDownload(albumID: albumID)
                return
            }

            // Check if already downloaded
            if let existingURL = try? await offlineStore.localFileURL(forTrackID: track.plexID),
               existingURL != nil {
                albumStates[albumID] = .downloading(completedTracks: index + 1, totalTracks: totalTracks)
                continue
            }

            // Wi-Fi check
            if wifiOnly && !isOnWifi() {
                logger.warning("Download aborted: Wi-Fi required but not connected for album '\(albumID, privacy: .public)'")
                albumStates[albumID] = .failed("Wi-Fi required")
                await cleanupFailedDownload(albumID: albumID)
                return
            }

            // Storage cap check
            do {
                let currentBytes = try await offlineStore.totalOfflineStorageBytes()
                if currentBytes >= storageLimitBytes {
                    logger.warning("Download aborted: storage limit reached for album '\(albumID, privacy: .public)'")
                    albumStates[albumID] = .failed("Storage limit reached")
                    await cleanupFailedDownload(albumID: albumID)
                    return
                }
            } catch {
                albumStates[albumID] = .failed("Failed to check storage")
                await cleanupFailedDownload(albumID: albumID)
                return
            }

            // Resolve URL and download
            do {
                let streamURL = try await library.streamURL(for: track)
                let (data, _) = try await session.data(from: streamURL)

                guard !Task.isCancelled else {
                    await cleanupFailedDownload(albumID: albumID)
                    return
                }

                let ext = streamURL.pathExtension.isEmpty ? "mp3" : streamURL.pathExtension
                let filename = "\(track.plexID)-\(UUID().uuidString).\(ext)"
                let fileURL = offlineDirectory.appendingPathComponent(filename)
                try data.write(to: fileURL, options: .atomic)

                let offlineTrack = OfflineTrack(
                    trackID: track.plexID,
                    albumID: albumID,
                    filename: filename,
                    downloadedAt: Date(),
                    fileSizeBytes: Int64(data.count)
                )
                try await offlineStore.saveOfflineTrack(offlineTrack)

                albumStates[albumID] = .downloading(completedTracks: index + 1, totalTracks: totalTracks)
                logger.info("Downloaded track \(index + 1)/\(totalTracks) for album '\(albumID, privacy: .public)'")
            } catch {
                guard !Task.isCancelled else {
                    await cleanupFailedDownload(albumID: albumID)
                    return
                }
                logger.error("Download failed for track '\(track.plexID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                albumStates[albumID] = .failed("Download failed")
                await cleanupFailedDownload(albumID: albumID)
                return
            }
        }

        albumStates[albumID] = .complete
        logger.info("Download complete for album '\(albumID, privacy: .public)' (\(totalTracks) tracks)")
    }

    private func cleanupFailedDownload(albumID: String) async {
        try? await offlineStore.deleteOfflineTracks(forAlbum: albumID)
    }

    private nonisolated func isOnWifi() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            result = path.usesInterfaceType(.wifi)
            semaphore.signal()
        }
        let queue = DispatchQueue(label: "holdings.chinlock.lunara.wifi-check")
        monitor.start(queue: queue)
        semaphore.wait()
        monitor.cancel()
        return result
    }
}
