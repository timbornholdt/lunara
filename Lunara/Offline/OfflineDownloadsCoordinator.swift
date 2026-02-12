import Foundation

actor OfflineDownloadsCoordinator: OfflineOpportunisticCaching, OfflineDownloadQueuing, OfflineDownloadStatusProviding, OfflineDownloadsLifecycleManaging {
    private let manifestStore: OfflineManifestStoring
    private let fileStore: OfflineFileStore
    private let trackFetcher: OfflineTrackFetching
    private let downloader: OfflineTrackDownloading
    private let wifiMonitor: WiFiReachabilityMonitoring
    private let nowProvider: () -> Date
    private let maxStorageBytes: Int64

    private var manifest: OfflineManifest
    private var pendingRequests: [PendingTrackRequest] = []
    private var inProgressTracks: [String: OfflineTrackProgress] = [:]
    private var progressSamples: [String: ProgressSample] = [:]
    private var canceledTrackKeys: Set<String> = []
    private var isProcessing = false

    static func make(
        manifestStore: OfflineManifestStoring,
        fileStore: OfflineFileStore,
        trackFetcher: OfflineTrackFetching,
        downloader: OfflineTrackDownloading,
        wifiMonitor: WiFiReachabilityMonitoring,
        nowProvider: @escaping () -> Date = Date.init,
        maxStorageBytes: Int64 = 120 * 1024 * 1024 * 1024
    ) -> OfflineDownloadsCoordinator {
        let coordinator = OfflineDownloadsCoordinator(
            manifestStore: manifestStore,
            fileStore: fileStore,
            trackFetcher: trackFetcher,
            downloader: downloader,
            wifiMonitor: wifiMonitor,
            nowProvider: nowProvider,
            maxStorageBytes: maxStorageBytes
        )
        wifiMonitor.setOnWiFiChangeHandler { [weak coordinator] isOnWiFi in
            guard let coordinator else { return }
            Task {
                await coordinator.handleWiFiStatusChange(isOnWiFi)
            }
        }
        return coordinator
    }

    init(
        manifestStore: OfflineManifestStoring,
        fileStore: OfflineFileStore,
        trackFetcher: OfflineTrackFetching,
        downloader: OfflineTrackDownloading,
        wifiMonitor: WiFiReachabilityMonitoring,
        nowProvider: @escaping () -> Date = Date.init,
        maxStorageBytes: Int64 = 120 * 1024 * 1024 * 1024
    ) {
        self.manifestStore = manifestStore
        self.fileStore = fileStore
        self.trackFetcher = trackFetcher
        self.downloader = downloader
        self.wifiMonitor = wifiMonitor
        self.nowProvider = nowProvider
        self.maxStorageBytes = maxStorageBytes
        self.manifest = (try? manifestStore.load()) ?? OfflineManifest()
    }

    func enqueueAlbumDownload(
        albumIdentity: String,
        displayTitle: String,
        artistName: String?,
        artworkPath: String?,
        albumRatingKeys: [String],
        source: OfflineDownloadSource
    ) async throws {
        try ensureCapacityForNewDownloads()

        let tracks = try await trackFetcher.fetchMergedTracks(albumRatingKeys: albumRatingKeys)
        upsertAlbumRecord(
            albumIdentity: albumIdentity,
            displayTitle: displayTitle,
            artistName: artistName,
            artworkPath: artworkPath,
            sourceAlbumRatingKeys: albumRatingKeys,
            tracks: tracks,
            source: source
        )

        for track in tracks {
            guard let partKey = track.media?.first?.parts.first?.key else {
                markTrackFailed(trackRatingKey: track.ratingKey, partKey: nil, source: source)
                continue
            }
            enqueueTrackIfNeeded(
                trackRatingKey: track.ratingKey,
                partKey: partKey,
                trackTitle: track.title,
                artistName: track.originalTitle ?? track.grandparentTitle ?? artistName,
                albumIdentity: albumIdentity,
                source: source
            )
        }

        try persistManifest()
        notifyDownloadsChanged()
        await processQueueIfNeeded()
    }

    func enqueueOpportunistic(current: PlexTrack, upcoming: [PlexTrack], limit: Int = 5) async {
        guard wifiMonitor.isOnWiFi else {
            return
        }

        let tracks = Array(([current] + upcoming).prefix(limit + 1))
        for track in tracks {
            guard let partKey = track.media?.first?.parts.first?.key else { continue }
            enqueueTrackIfNeeded(
                trackRatingKey: track.ratingKey,
                partKey: partKey,
                trackTitle: track.title,
                artistName: track.originalTitle ?? track.grandparentTitle,
                albumIdentity: track.parentRatingKey,
                source: .opportunistic
            )
        }

        try? persistManifest()
        notifyDownloadsChanged()
        await processQueueIfNeeded()
    }

    func snapshot() -> OfflineDownloadQueueSnapshot {
        let pendingTracks = pendingRequests.map { request in
            makeProgress(
                trackRatingKey: request.trackRatingKey,
                trackTitle: request.trackTitle,
                albumIdentity: request.albumIdentity,
                bytesReceived: 0,
                expectedBytes: nil,
                bytesPerSecond: nil,
                estimatedRemainingSeconds: nil
            )
        }
        .sorted { lhs, rhs in
            lhs.trackRatingKey < rhs.trackRatingKey
        }
        let progress = inProgressTracks.values.sorted { lhs, rhs in
            lhs.trackRatingKey < rhs.trackRatingKey
        }
        return OfflineDownloadQueueSnapshot(
            pendingTracks: pendingTracks,
            inProgressTracks: progress
        )
    }

    func handleWiFiStatusChange(_ isOnWiFi: Bool) async {
        guard isOnWiFi else { return }
        await processQueueIfNeeded()
    }

    func completedFileCount() -> Int {
        manifest.completedFileCount
    }

    func manageDownloadsSnapshot() -> OfflineManageDownloadsSnapshot {
        let queueSnapshot = snapshot()

        let downloadedAlbums = manifest.albums.values
            .filter { $0.isExplicit }
            .compactMap { album -> OfflineDownloadedAlbumSummary? in
                let completedCount = album.trackKeys.filter { trackKey in
                    manifest.tracks[trackKey]?.state == .completed
                }.count
                guard completedCount > 0 else { return nil }
                return OfflineDownloadedAlbumSummary(
                    albumIdentity: album.albumIdentity,
                    displayTitle: album.displayTitle,
                    artistName: album.artistName,
                    artworkPath: album.artworkPath,
                    albumRatingKeys: album.sourceAlbumRatingKeys,
                    completedTrackCount: completedCount,
                    totalTrackCount: album.trackKeys.count,
                    collectionMembershipCount: album.collectionKeys.count
                )
            }
            .sorted { lhs, rhs in
                lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }

        let downloadedCollections = manifest.collections.values
            .map { collection in
                OfflineDownloadedCollectionSummary(
                    collectionKey: collection.collectionKey,
                    title: collection.title,
                    albumCount: collection.albumIdentities.count
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let streamCachedTracks = manifest.tracks.values
            .filter { $0.state == .completed && $0.isOpportunistic }
            .map { track in
                OfflineStreamCachedTrackSummary(
                    trackRatingKey: track.trackRatingKey,
                    albumIdentity: manifest.albums.values.first(where: { $0.trackKeys.contains(track.trackRatingKey) })?.albumIdentity,
                    completedAt: track.completedAt
                )
            }
            .sorted { lhs, rhs in
                lhs.trackRatingKey.localizedCaseInsensitiveCompare(rhs.trackRatingKey) == .orderedAscending
            }

        return OfflineManageDownloadsSnapshot(
            queue: queueSnapshot,
            downloadedAlbums: downloadedAlbums,
            downloadedCollections: downloadedCollections,
            streamCachedTracks: streamCachedTracks
        )
    }

    func albumDownloadProgress(albumIdentity: String) -> OfflineAlbumDownloadProgress? {
        guard let album = manifest.albums[albumIdentity] else { return nil }
        let albumTrackKeys = Set(album.trackKeys)
        guard albumTrackKeys.isEmpty == false else { return nil }

        let completedTrackCount = album.trackKeys.reduce(into: 0) { partial, trackKey in
            if manifest.tracks[trackKey]?.state == .completed {
                partial += 1
            }
        }

        let pendingTrackCount = pendingRequests.reduce(into: 0) { partial, request in
            if albumTrackKeys.contains(request.trackRatingKey) {
                partial += 1
            }
        }

        let albumInProgress = inProgressTracks.values.filter { progress in
            if let progressAlbumIdentity = progress.albumIdentity {
                return progressAlbumIdentity == albumIdentity
            }
            return albumTrackKeys.contains(progress.trackRatingKey)
        }
        let inProgressTrackCount = albumInProgress.count

        let partialInProgressTrackUnits = albumInProgress.reduce(into: 0.0) { partial, progress in
            guard let expected = progress.expectedBytes, expected > 0 else { return }
            let trackFraction = min(max(Double(progress.bytesReceived) / Double(expected), 0), 1)
            partial += trackFraction
        }

        return OfflineAlbumDownloadProgress(
            albumIdentity: albumIdentity,
            totalTrackCount: album.trackKeys.count,
            completedTrackCount: completedTrackCount,
            pendingTrackCount: pendingTrackCount,
            inProgressTrackCount: inProgressTrackCount,
            partialInProgressTrackUnits: partialInProgressTrackUnits
        )
    }

    func upsertCollectionRecord(
        collectionKey: String,
        title: String,
        albumIdentities: [String]
    ) async throws {
        let sortedIdentities = Array(Set(albumIdentities)).sorted()
        manifest.collections[collectionKey] = OfflineCollectionRecord(
            collectionKey: collectionKey,
            title: title,
            albumIdentities: sortedIdentities,
            lastReconciledAt: nowProvider()
        )
        try persistManifest()
        notifyDownloadsChanged()
    }

    func downloadedCollectionKeys() async -> [String] {
        Array(manifest.collections.keys).sorted()
    }

    func reconcileCollectionDownload(
        collectionKey: String,
        title: String,
        albumGroups: [OfflineCollectionAlbumGroup]
    ) async throws {
        let uniqueGroups = dedupedGroups(albumGroups)
        let liveIdentities = uniqueGroups.map(\.albumIdentity)
        let previousIdentities = manifest.collections[collectionKey]?.albumIdentities ?? []
        let removedIdentities = Set(previousIdentities).subtracting(Set(liveIdentities))

        manifest.collections[collectionKey] = OfflineCollectionRecord(
            collectionKey: collectionKey,
            title: title,
            albumIdentities: liveIdentities,
            lastReconciledAt: nowProvider()
        )

        for albumIdentity in removedIdentities {
            guard var album = manifest.albums[albumIdentity] else { continue }
            album.collectionKeys.removeAll { $0 == collectionKey }
            manifest.albums[albumIdentity] = album
            try removeAlbumIfNoOwnership(albumIdentity: albumIdentity)
        }

        try persistManifest()

        for group in uniqueGroups {
            try await enqueueAlbumDownload(
                albumIdentity: group.albumIdentity,
                displayTitle: group.displayTitle,
                artistName: group.artistName,
                artworkPath: group.artworkPath,
                albumRatingKeys: group.albumRatingKeys,
                source: .collection(collectionKey)
            )
        }
    }

    func cancelTrackDownload(trackRatingKey: String) async throws {
        canceledTrackKeys.insert(trackRatingKey)

        if let pendingIndex = pendingRequests.firstIndex(where: { $0.trackRatingKey == trackRatingKey }) {
            pendingRequests.remove(at: pendingIndex)
            progressSamples.removeValue(forKey: trackRatingKey)
            manifest.tracks[trackRatingKey]?.state = .failed
            try persistManifest()
            notifyDownloadsChanged()
        }
    }

    func removeAlbumDownload(albumIdentity: String) async throws {
        guard var album = manifest.albums[albumIdentity] else { return }
        album.isExplicit = false
        manifest.albums[albumIdentity] = album
        try removeAlbumIfNoOwnership(albumIdentity: albumIdentity)
        try persistManifest()
        notifyDownloadsChanged()
    }

    func removeCollectionDownload(collectionKey: String) async throws {
        let removedIdentities = manifest.collections[collectionKey]?.albumIdentities ?? []
        manifest.collections.removeValue(forKey: collectionKey)

        for albumIdentity in removedIdentities {
            guard var album = manifest.albums[albumIdentity] else { continue }
            album.collectionKeys.removeAll { $0 == collectionKey }
            manifest.albums[albumIdentity] = album
            try removeAlbumIfNoOwnership(albumIdentity: albumIdentity)
        }
        try persistManifest()
        notifyDownloadsChanged()
    }

    func purgeAll() async throws {
        try fileStore.removeAll()
        manifest = OfflineManifest()
        pendingRequests.removeAll()
        inProgressTracks.removeAll()
        progressSamples.removeAll()
        canceledTrackKeys.removeAll()
        try manifestStore.clear()
        notifyDownloadsChanged()
    }

    private func processQueueIfNeeded() async {
        guard wifiMonitor.isOnWiFi else { return }
        guard isProcessing == false else { return }

        isProcessing = true
        defer { isProcessing = false }

        while wifiMonitor.isOnWiFi && pendingRequests.isEmpty == false {
            let request = pendingRequests.removeFirst()
            await process(request)
        }
    }

    private func process(_ request: PendingTrackRequest) async {
        if canceledTrackKeys.contains(request.trackRatingKey) {
            canceledTrackKeys.remove(request.trackRatingKey)
            manifest.tracks[request.trackRatingKey]?.state = .failed
            try? persistManifest()
            return
        }

        inProgressTracks[request.trackRatingKey] = OfflineTrackProgress(
            trackRatingKey: request.trackRatingKey,
            trackTitle: request.trackTitle,
            albumIdentity: request.albumIdentity,
            albumTitle: manifest.albums[request.albumIdentity ?? ""]?.displayTitle,
            artistName: request.artistName ?? manifest.albums[request.albumIdentity ?? ""]?.artistName,
            artworkPath: manifest.albums[request.albumIdentity ?? ""]?.artworkPath,
            bytesReceived: 0,
            expectedBytes: nil,
            bytesPerSecond: nil,
            estimatedRemainingSeconds: nil
        )
        progressSamples[request.trackRatingKey] = ProgressSample(bytesReceived: 0, timestamp: nowProvider())

        manifest.tracks[request.trackRatingKey] = OfflineTrackRecord(
            trackRatingKey: request.trackRatingKey,
            trackTitle: request.trackTitle,
            artistName: request.artistName,
            partKey: request.partKey,
            relativeFilePath: nil,
            expectedBytes: nil,
            actualBytes: nil,
            state: .inProgress,
            isOpportunistic: request.source.isOpportunistic,
            lastPlayedAt: manifest.tracks[request.trackRatingKey]?.lastPlayedAt,
            completedAt: nil
        )
        try? persistManifest()
        notifyDownloadsChanged()

        do {
            let payload = try await downloader.downloadTrack(
                trackRatingKey: request.trackRatingKey,
                partKey: request.partKey,
                progress: { [weak self] received, expected in
                    guard let self else { return }
                    Task {
                        await self.updateProgress(
                            trackRatingKey: request.trackRatingKey,
                            albumIdentity: request.albumIdentity,
                            bytesReceived: received,
                            expectedBytes: expected
                        )
                    }
                }
            )

            try verify(payload, trackRatingKey: request.trackRatingKey)
            let relativePath = fileStore.makeTrackRelativePath(
                trackRatingKey: request.trackRatingKey,
                partKey: request.partKey,
                fileExtension: payload.suggestedFileExtension
            )
            try fileStore.write(payload.data, toRelativePath: relativePath)

            if canceledTrackKeys.contains(request.trackRatingKey) {
                canceledTrackKeys.remove(request.trackRatingKey)
                try fileStore.removeFile(atRelativePath: relativePath)
                throw OfflineDownloadError.incompleteDownload(request.trackRatingKey)
            }

            manifest.tracks[request.trackRatingKey] = OfflineTrackRecord(
                trackRatingKey: request.trackRatingKey,
                trackTitle: request.trackTitle,
                artistName: request.artistName,
                partKey: request.partKey,
                relativeFilePath: relativePath,
                expectedBytes: payload.expectedBytes,
                actualBytes: payload.actualBytes,
                state: .completed,
                isOpportunistic: request.source.isOpportunistic,
                lastPlayedAt: manifest.tracks[request.trackRatingKey]?.lastPlayedAt,
                completedAt: nowProvider()
            )
            try enforceStorageCapIfNeeded()
        } catch {
            markTrackFailed(
                trackRatingKey: request.trackRatingKey,
                partKey: request.partKey,
                source: request.source
            )
        }

        inProgressTracks.removeValue(forKey: request.trackRatingKey)
        progressSamples.removeValue(forKey: request.trackRatingKey)
        try? persistManifest()
        notifyDownloadsChanged()
    }

    private func updateProgress(
        trackRatingKey: String,
        albumIdentity: String?,
        bytesReceived: Int64,
        expectedBytes: Int64?
    ) {
        let now = nowProvider()
        let previousSample = progressSamples[trackRatingKey]
        let previousProgress = inProgressTracks[trackRatingKey]

        var bytesPerSecond: Double?
        if let previousSample {
            let elapsed = now.timeIntervalSince(previousSample.timestamp)
            let deltaBytes = bytesReceived - previousSample.bytesReceived
            if elapsed > 0, deltaBytes >= 0 {
                bytesPerSecond = Double(deltaBytes) / elapsed
            }
        }
        progressSamples[trackRatingKey] = ProgressSample(bytesReceived: bytesReceived, timestamp: now)

        var estimatedRemainingSeconds: TimeInterval?
        if let expectedBytes,
           let bytesPerSecond,
           bytesPerSecond > 0 {
            let remaining = max(expectedBytes - bytesReceived, 0)
            estimatedRemainingSeconds = Double(remaining) / bytesPerSecond
        }

        let updated = makeProgress(
            trackRatingKey: trackRatingKey,
            trackTitle: previousProgress?.trackTitle,
            albumIdentity: albumIdentity ?? previousProgress?.albumIdentity,
            bytesReceived: bytesReceived,
            expectedBytes: expectedBytes,
            bytesPerSecond: bytesPerSecond,
            estimatedRemainingSeconds: estimatedRemainingSeconds
        )
        inProgressTracks[trackRatingKey] = updated
        notifyDownloadsChanged()
    }

    private func verify(_ payload: OfflineDownloadedPayload, trackRatingKey: String) throws {
        guard payload.actualBytes > 0 else {
            throw OfflineDownloadError.incompleteDownload(trackRatingKey)
        }
        if let expected = payload.expectedBytes,
           expected > 0,
           payload.actualBytes != expected {
            throw OfflineDownloadError.incompleteDownload(trackRatingKey)
        }
    }

    private func upsertAlbumRecord(
        albumIdentity: String,
        displayTitle: String,
        artistName: String?,
        artworkPath: String?,
        sourceAlbumRatingKeys: [String],
        tracks: [PlexTrack],
        source: OfflineDownloadSource
    ) {
        let existing = manifest.albums[albumIdentity]
        var trackKeys = existing?.trackKeys ?? []
        for key in tracks.map(\ .ratingKey) where trackKeys.contains(key) == false {
            trackKeys.append(key)
        }

        var collectionKeys = existing?.collectionKeys ?? []
        if case .collection(let collectionKey) = source,
           collectionKeys.contains(collectionKey) == false {
            collectionKeys.append(collectionKey)
        }
        let mergedSourceAlbumRatingKeys = Array(
            Set((existing?.sourceAlbumRatingKeys ?? []) + sourceAlbumRatingKeys)
        ).sorted()

        manifest.albums[albumIdentity] = OfflineAlbumRecord(
            albumIdentity: albumIdentity,
            displayTitle: displayTitle,
            artistName: artistName ?? existing?.artistName,
            artworkPath: artworkPath ?? existing?.artworkPath,
            sourceAlbumRatingKeys: mergedSourceAlbumRatingKeys,
            trackKeys: trackKeys,
            isExplicit: (existing?.isExplicit ?? false) || source == .explicitAlbum,
            collectionKeys: collectionKeys
        )
    }

    private func enqueueTrackIfNeeded(
        trackRatingKey: String,
        partKey: String,
        trackTitle: String?,
        artistName: String?,
        albumIdentity: String?,
        source: OfflineDownloadSource
    ) {
        if let existing = manifest.tracks[trackRatingKey], existing.state == .completed {
            return
        }
        if pendingRequests.contains(where: { $0.trackRatingKey == trackRatingKey }) {
            return
        }
        if inProgressTracks[trackRatingKey] != nil {
            return
        }

        let request = PendingTrackRequest(
            trackRatingKey: trackRatingKey,
            partKey: partKey,
            trackTitle: trackTitle,
            artistName: artistName,
            albumIdentity: albumIdentity,
            source: source
        )
        pendingRequests.append(request)
        manifest.tracks[trackRatingKey] = OfflineTrackRecord(
            trackRatingKey: trackRatingKey,
            trackTitle: trackTitle,
            artistName: artistName,
            partKey: partKey,
            relativeFilePath: nil,
            expectedBytes: nil,
            actualBytes: nil,
            state: .pending,
            isOpportunistic: source.isOpportunistic,
            lastPlayedAt: manifest.tracks[trackRatingKey]?.lastPlayedAt,
            completedAt: nil
        )
    }

    private func markTrackFailed(
        trackRatingKey: String,
        partKey: String?,
        source: OfflineDownloadSource
    ) {
        if let relativePath = manifest.tracks[trackRatingKey]?.relativeFilePath {
            try? fileStore.removeFile(atRelativePath: relativePath)
        }
        manifest.tracks[trackRatingKey] = OfflineTrackRecord(
            trackRatingKey: trackRatingKey,
            trackTitle: manifest.tracks[trackRatingKey]?.trackTitle,
            artistName: manifest.tracks[trackRatingKey]?.artistName,
            partKey: partKey,
            relativeFilePath: nil,
            expectedBytes: nil,
            actualBytes: nil,
            state: .failed,
            isOpportunistic: source.isOpportunistic,
            lastPlayedAt: manifest.tracks[trackRatingKey]?.lastPlayedAt,
            completedAt: nil
        )
    }

    private func removeAlbumIfNoOwnership(albumIdentity: String) throws {
        guard let album = manifest.albums[albumIdentity] else { return }
        if album.isExplicit || album.collectionKeys.isEmpty == false {
            return
        }

        for trackKey in album.trackKeys {
            if let relativePath = manifest.tracks[trackKey]?.relativeFilePath {
                try? fileStore.removeFile(atRelativePath: relativePath)
            }
            manifest.tracks.removeValue(forKey: trackKey)
        }
        manifest.albums.removeValue(forKey: albumIdentity)
    }

    private func ensureCapacityForNewDownloads() throws {
        syncManifestFromDisk()
        try enforceStorageCapIfNeeded()
    }

    private func enforceStorageCapIfNeeded() throws {
        guard manifest.totalBytes > maxStorageBytes else { return }

        let evictableTrackKeys = manifest.tracks.values
            .filter { record in
                record.state == .completed && isEvictable(trackKey: record.trackRatingKey)
            }
            .sorted { lhs, rhs in
                switch (lhs.lastPlayedAt, rhs.lastPlayedAt) {
                case let (.some(left), .some(right)):
                    return left < right
                case (.none, .some):
                    return true
                case (.some, .none):
                    return false
                case (.none, .none):
                    return lhs.trackRatingKey < rhs.trackRatingKey
                }
            }
            .map(\.trackRatingKey)

        for trackKey in evictableTrackKeys where manifest.totalBytes > maxStorageBytes {
            try removeTrackCompletely(trackKey: trackKey)
        }

        guard manifest.totalBytes <= maxStorageBytes else {
            throw OfflineDownloadError.insufficientStorageNonEvictable
        }
    }

    private func isEvictable(trackKey: String) -> Bool {
        let owners = manifest.albums.values.filter { $0.trackKeys.contains(trackKey) }
        return owners.contains { $0.isExplicit } == false
    }

    private func removeTrackCompletely(trackKey: String) throws {
        if let relativePath = manifest.tracks[trackKey]?.relativeFilePath {
            try? fileStore.removeFile(atRelativePath: relativePath)
        }

        pendingRequests.removeAll { $0.trackRatingKey == trackKey }
        inProgressTracks.removeValue(forKey: trackKey)
        progressSamples.removeValue(forKey: trackKey)
        canceledTrackKeys.remove(trackKey)
        manifest.tracks.removeValue(forKey: trackKey)

        var removedAlbumIdentities: [String] = []
        for (albumIdentity, var album) in manifest.albums {
            guard album.trackKeys.contains(trackKey) else { continue }
            album.trackKeys.removeAll { $0 == trackKey }
            if album.trackKeys.isEmpty {
                removedAlbumIdentities.append(albumIdentity)
            }
            manifest.albums[albumIdentity] = album
        }

        for albumIdentity in removedAlbumIdentities {
            manifest.albums.removeValue(forKey: albumIdentity)
            for (collectionKey, var collection) in manifest.collections {
                collection.albumIdentities.removeAll { $0 == albumIdentity }
                manifest.collections[collectionKey] = collection
            }
        }
    }

    private func dedupedGroups(_ groups: [OfflineCollectionAlbumGroup]) -> [OfflineCollectionAlbumGroup] {
        var byIdentity: [String: OfflineCollectionAlbumGroup] = [:]
        for group in groups {
            if var existing = byIdentity[group.albumIdentity] {
                let mergedKeys = Array(Set(existing.albumRatingKeys + group.albumRatingKeys)).sorted()
                existing = OfflineCollectionAlbumGroup(
                    albumIdentity: existing.albumIdentity,
                    displayTitle: existing.displayTitle,
                    artistName: existing.artistName ?? group.artistName,
                    artworkPath: existing.artworkPath ?? group.artworkPath,
                    albumRatingKeys: mergedKeys
                )
                byIdentity[group.albumIdentity] = existing
            } else {
                byIdentity[group.albumIdentity] = OfflineCollectionAlbumGroup(
                    albumIdentity: group.albumIdentity,
                    displayTitle: group.displayTitle,
                    artistName: group.artistName,
                    artworkPath: group.artworkPath,
                    albumRatingKeys: Array(Set(group.albumRatingKeys)).sorted()
                )
            }
        }
        return byIdentity.values.sorted { lhs, rhs in
            lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
    }

    private func persistManifest() throws {
        try manifestStore.save(manifest)
    }

    private func syncManifestFromDisk() {
        if let latest = try? manifestStore.load() {
            manifest = latest
        }
    }

    private func makeProgress(
        trackRatingKey: String,
        trackTitle: String?,
        albumIdentity: String?,
        bytesReceived: Int64,
        expectedBytes: Int64?,
        bytesPerSecond: Double?,
        estimatedRemainingSeconds: TimeInterval?
    ) -> OfflineTrackProgress {
        let album = albumIdentity.flatMap { manifest.albums[$0] } ??
            manifest.albums.values.first(where: { $0.trackKeys.contains(trackRatingKey) })
        let resolvedAlbumIdentity = albumIdentity ?? album?.albumIdentity
        return OfflineTrackProgress(
            trackRatingKey: trackRatingKey,
            trackTitle: trackTitle ?? manifest.tracks[trackRatingKey]?.trackTitle,
            albumIdentity: resolvedAlbumIdentity,
            albumTitle: album?.displayTitle,
            artistName: manifest.tracks[trackRatingKey]?.artistName ?? album?.artistName,
            artworkPath: album?.artworkPath,
            bytesReceived: bytesReceived,
            expectedBytes: expectedBytes,
            bytesPerSecond: bytesPerSecond,
            estimatedRemainingSeconds: estimatedRemainingSeconds
        )
    }

    private func notifyDownloadsChanged() {
        NotificationCenter.default.post(name: .offlineDownloadsDidChange, object: nil)
    }
}

private struct PendingTrackRequest: Equatable {
    let trackRatingKey: String
    let partKey: String
    let trackTitle: String?
    let artistName: String?
    let albumIdentity: String?
    let source: OfflineDownloadSource
}

private struct ProgressSample: Equatable {
    let bytesReceived: Int64
    let timestamp: Date
}
