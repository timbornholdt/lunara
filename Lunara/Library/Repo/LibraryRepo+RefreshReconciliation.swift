import Foundation
import os

extension LibraryRepo {
    private struct ReconciliationDelta {
        let newAlbumIDs: [String]
        let changedAlbumIDs: [String]
        let unchangedAlbumIDs: [String]
        let deletedAlbumIDs: [String]
    }

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        let refreshedAt = nowProvider()
        let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "LibraryRefresh")

        do {
            async let remoteArtistsTask = remote.fetchArtists()
            async let remoteCollectionsTask = remote.fetchCollections()
            async let remotePlaylistsTask = remote.fetchPlaylists()
            let remoteAlbums = try await remote.fetchAlbums()
            let remoteArtists = try await remoteArtistsTask
            let remoteCollections = try await remoteCollectionsTask
            let remotePlaylists = try await remotePlaylistsTask
            let remotePlaylistItems = try await fetchRemotePlaylistItems(for: remotePlaylists)
            let dedupedLibrary = dedupeLibrary(albums: remoteAlbums, tracks: [])

            let cachedAlbums = try await fetchAllCachedAlbums()
            logger.info(
                "refresh start reason=\(String(describing: reason), privacy: .public) cachedAlbums=\(cachedAlbums.count)"
            )
            logger.info(
                """
                refresh remote reason=\(String(describing: reason), privacy: .public) \
                remoteAlbums=\(remoteAlbums.count) remoteArtists=\(remoteArtists.count) remoteCollections=\(remoteCollections.count) remotePlaylists=\(remotePlaylists.count) \
                dedupedAlbums=\(dedupedLibrary.albums.count)
                """
            )
            let delta = buildReconciliationDelta(
                cachedAlbums: cachedAlbums,
                remoteAlbums: dedupedLibrary.albums
            )
            logger.info(
                """
                refresh delta reason=\(String(describing: reason), privacy: .public) \
                albums[new=\(delta.newAlbumIDs.count),changed=\(delta.changedAlbumIDs.count),unchanged=\(delta.unchangedAlbumIDs.count),deleted=\(delta.deletedAlbumIDs.count)]
                """
            )

            let run = try await store.beginIncrementalSync(startedAt: refreshedAt)
            try await persistReconciliationDelta(delta, in: run, refreshedAt: refreshedAt)
            try await store.upsertAlbums(dedupedLibrary.albums, in: run)
            try await store.replaceArtists(remoteArtists, in: run)
            try await store.replaceCollections(remoteCollections, in: run)
            try await store.upsertPlaylists(remotePlaylists.map {
                LibraryPlaylistSnapshot(
                    plexID: $0.plexID,
                    title: $0.title,
                    trackCount: $0.trackCount,
                    updatedAt: $0.updatedAt,
                    thumbURL: $0.thumb
                )
            }, in: run)
            for (playlistID, items) in remotePlaylistItems {
                try await store.upsertPlaylistItems(
                    items.map { LibraryPlaylistItemSnapshot(trackID: $0.trackID, position: $0.position, playlistItemID: $0.playlistItemID) },
                    playlistID: playlistID,
                    in: run
                )
            }
            try await store.markAlbumsSeen(dedupedLibrary.albums.map(\.plexID), in: run)
            try await store.markTracksWithValidAlbumsSeen(in: run)
            let pruneResult = try await store.pruneRowsNotSeen(in: run)
            logger.info(
                "refresh prune reason=\(String(describing: reason), privacy: .public) prunedAlbums=\(pruneResult.prunedAlbumIDs.count) prunedTracks=\(pruneResult.prunedTrackIDs.count)"
            )
            try await store.completeIncrementalSync(run, refreshedAt: refreshedAt)

            let dedupedAlbums = dedupedLibrary.albums
            let cachedAlbumsByID = Dictionary(uniqueKeysWithValues: cachedAlbums.map { ($0.plexID, $0) })
            Task { [weak self] in
                guard let self else {
                    return
                }
                await self.reconcileThumbnailArtwork(
                    cachedAlbumsByID: cachedAlbumsByID,
                    refreshedAlbums: dedupedAlbums,
                    deletedAlbumIDs: pruneResult.prunedAlbumIDs
                )
            }

            let cachedArtists = try await store.fetchArtists()
            let cachedCollections = try await store.fetchCollections()
            logger.info(
                "refresh complete reason=\(String(describing: reason), privacy: .public) refreshedAt=\(refreshedAt.timeIntervalSince1970) albums=\(dedupedLibrary.albums.count) artists=\(cachedArtists.count) collections=\(cachedCollections.count)"
            )
            return LibraryRefreshOutcome(
                reason: reason,
                refreshedAt: refreshedAt,
                albumCount: dedupedLibrary.albums.count,
                trackCount: 0,
                artistCount: cachedArtists.count,
                collectionCount: cachedCollections.count
            )
        } catch let error as LibraryError {
            logger.error(
                "refresh failed reason=\(String(describing: reason), privacy: .public) error=\(error.userMessage, privacy: .public)"
            )
            throw error
        } catch {
            logger.error(
                "refresh failed reason=\(String(describing: reason), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw LibraryError.operationFailed(reason: "Library refresh failed: \(error.localizedDescription)")
        }
    }

    private func fetchRemotePlaylistItems(
        for playlists: [LibraryRemotePlaylist]
    ) async throws -> [String: [LibraryRemotePlaylistItem]] {
        var itemsByPlaylistID: [String: [LibraryRemotePlaylistItem]] = [:]
        itemsByPlaylistID.reserveCapacity(playlists.count)
        for playlist in playlists {
            itemsByPlaylistID[playlist.plexID] = try await remote.fetchPlaylistItems(playlistID: playlist.plexID)
        }
        return itemsByPlaylistID
    }

    private func fetchAllCachedAlbums(pageSize: Int = 200) async throws -> [Album] {
        var allAlbums: [Album] = []
        var pageNumber = 1

        while true {
            let page = LibraryPage(number: pageNumber, size: pageSize)
            let batch = try await store.fetchAlbums(page: page)
            allAlbums.append(contentsOf: batch)

            if batch.count < pageSize {
                break
            }

            pageNumber += 1
        }

        return allAlbums
    }

    private func buildReconciliationDelta(
        cachedAlbums: [Album],
        remoteAlbums: [Album]
    ) -> ReconciliationDelta {
        let albumDelta = categorizeRows(cached: cachedAlbums, remote: remoteAlbums, id: \.plexID)

        return ReconciliationDelta(
            newAlbumIDs: albumDelta.newIDs,
            changedAlbumIDs: albumDelta.changedIDs,
            unchangedAlbumIDs: albumDelta.unchangedIDs,
            deletedAlbumIDs: albumDelta.deletedIDs
        )
    }

    private func persistReconciliationDelta(
        _ delta: ReconciliationDelta,
        in run: LibrarySyncRun,
        refreshedAt: Date
    ) async throws {
        let checkpoints = [
            LibrarySyncCheckpoint(
                key: "reconciliation.albums.new",
                value: String(delta.newAlbumIDs.count),
                updatedAt: refreshedAt
            ),
            LibrarySyncCheckpoint(
                key: "reconciliation.albums.changed",
                value: String(delta.changedAlbumIDs.count),
                updatedAt: refreshedAt
            ),
            LibrarySyncCheckpoint(
                key: "reconciliation.albums.unchanged",
                value: String(delta.unchangedAlbumIDs.count),
                updatedAt: refreshedAt
            ),
            LibrarySyncCheckpoint(
                key: "reconciliation.albums.deleted",
                value: String(delta.deletedAlbumIDs.count),
                updatedAt: refreshedAt
            )
        ]

        for checkpoint in checkpoints {
            try await store.setSyncCheckpoint(checkpoint, in: run)
        }
    }

    private func categorizeRows<Row: Equatable>(
        cached: [Row],
        remote: [Row],
        id: KeyPath<Row, String>
    ) -> (newIDs: [String], changedIDs: [String], unchangedIDs: [String], deletedIDs: [String]) {
        let cachedByID = Dictionary(uniqueKeysWithValues: cached.map { ($0[keyPath: id], $0) })
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0[keyPath: id], $0) })

        var newIDs: [String] = []
        var changedIDs: [String] = []
        var unchangedIDs: [String] = []

        for (rowID, remoteRow) in remoteByID {
            guard let cachedRow = cachedByID[rowID] else {
                newIDs.append(rowID)
                continue
            }

            if cachedRow == remoteRow {
                unchangedIDs.append(rowID)
            } else {
                changedIDs.append(rowID)
            }
        }

        let deletedIDs = cachedByID.keys.filter { remoteByID[$0] == nil }

        return (
            newIDs.sorted(),
            changedIDs.sorted(),
            unchangedIDs.sorted(),
            deletedIDs.sorted()
        )
    }
}
