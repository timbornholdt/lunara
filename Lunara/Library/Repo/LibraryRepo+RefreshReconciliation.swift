import Foundation

extension LibraryRepo {
    private struct ReconciliationDelta {
        let newAlbumIDs: [String]
        let changedAlbumIDs: [String]
        let unchangedAlbumIDs: [String]
        let deletedAlbumIDs: [String]
        let newTrackIDs: [String]
        let changedTrackIDs: [String]
        let unchangedTrackIDs: [String]
        let deletedTrackIDs: [String]
    }

    func refreshLibrary(reason: LibraryRefreshReason) async throws -> LibraryRefreshOutcome {
        let refreshedAt = nowProvider()

        do {
            let remoteAlbums = try await remote.fetchAlbums()
            let remoteTracks = try await fetchRemoteTracks(for: remoteAlbums)
            let dedupedLibrary = dedupeLibrary(albums: remoteAlbums, tracks: remoteTracks)

            let cachedAlbums = try await fetchAllCachedAlbums()
            let cachedTracks = try await fetchTracks(for: cachedAlbums)
            let delta = buildReconciliationDelta(
                cachedAlbums: cachedAlbums,
                cachedTracks: cachedTracks,
                remoteAlbums: dedupedLibrary.albums,
                remoteTracks: dedupedLibrary.tracks
            )

            let run = try await store.beginIncrementalSync(startedAt: refreshedAt)
            try await persistReconciliationDelta(delta, in: run, refreshedAt: refreshedAt)
            try await store.upsertAlbums(dedupedLibrary.albums, in: run)
            try await store.upsertTracks(dedupedLibrary.tracks, in: run)
            try await store.markAlbumsSeen(dedupedLibrary.albums.map(\.plexID), in: run)
            try await store.markTracksSeen(dedupedLibrary.tracks.map(\.plexID), in: run)
            _ = try await store.pruneRowsNotSeen(in: run)
            try await store.completeIncrementalSync(run, refreshedAt: refreshedAt)

            let dedupedAlbums = dedupedLibrary.albums
            Task { [weak self] in
                guard let self else {
                    return
                }
                await self.preloadThumbnailArtwork(for: dedupedAlbums)
            }

            let cachedArtists = try await store.fetchArtists()
            let cachedCollections = try await store.fetchCollections()
            return LibraryRefreshOutcome(
                reason: reason,
                refreshedAt: refreshedAt,
                albumCount: dedupedLibrary.albums.count,
                trackCount: dedupedLibrary.tracks.count,
                artistCount: cachedArtists.count,
                collectionCount: cachedCollections.count
            )
        } catch let error as LibraryError {
            throw error
        } catch {
            throw LibraryError.operationFailed(reason: "Library refresh failed: \(error.localizedDescription)")
        }
    }

    private func fetchRemoteTracks(for albums: [Album]) async throws -> [Track] {
        var tracks: [Track] = []
        for album in albums {
            let albumTracks = try await remote.fetchTracks(forAlbum: album.plexID)
            tracks.append(contentsOf: albumTracks)
        }
        return tracks
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

    private func fetchTracks(for albums: [Album]) async throws -> [Track] {
        var tracks: [Track] = []
        for album in albums {
            let albumTracks = try await store.fetchTracks(forAlbum: album.plexID)
            tracks.append(contentsOf: albumTracks)
        }
        return tracks
    }

    private func buildReconciliationDelta(
        cachedAlbums: [Album],
        cachedTracks: [Track],
        remoteAlbums: [Album],
        remoteTracks: [Track]
    ) -> ReconciliationDelta {
        let albumDelta = categorizeRows(cached: cachedAlbums, remote: remoteAlbums, id: \.plexID)
        let trackDelta = categorizeRows(cached: cachedTracks, remote: remoteTracks, id: \.plexID)

        return ReconciliationDelta(
            newAlbumIDs: albumDelta.newIDs,
            changedAlbumIDs: albumDelta.changedIDs,
            unchangedAlbumIDs: albumDelta.unchangedIDs,
            deletedAlbumIDs: albumDelta.deletedIDs,
            newTrackIDs: trackDelta.newIDs,
            changedTrackIDs: trackDelta.changedIDs,
            unchangedTrackIDs: trackDelta.unchangedIDs,
            deletedTrackIDs: trackDelta.deletedIDs
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
            ),
            LibrarySyncCheckpoint(
                key: "reconciliation.tracks.new",
                value: String(delta.newTrackIDs.count),
                updatedAt: refreshedAt
            ),
            LibrarySyncCheckpoint(
                key: "reconciliation.tracks.changed",
                value: String(delta.changedTrackIDs.count),
                updatedAt: refreshedAt
            ),
            LibrarySyncCheckpoint(
                key: "reconciliation.tracks.unchanged",
                value: String(delta.unchangedTrackIDs.count),
                updatedAt: refreshedAt
            ),
            LibrarySyncCheckpoint(
                key: "reconciliation.tracks.deleted",
                value: String(delta.deletedTrackIDs.count),
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
