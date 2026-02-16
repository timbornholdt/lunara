import Combine
import Foundation
import UIKit

@MainActor
final class PlaybackViewModel: ObservableObject, PlaybackControlling {
    @Published private(set) var nowPlaying: NowPlayingState?
    @Published private(set) var nowPlayingContext: NowPlayingContext?
    @Published private(set) var albumTheme: AlbumTheme?
    @Published private(set) var errorMessage: String?
    @Published private(set) var upNextTracks: [PlexTrack] = []

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let engineFactory: PlaybackEngineFactory
    private var engine: PlaybackEngineing?
    private var lastServerURL: URL?
    private var lastToken: String?
    private let bypassAuthChecks: Bool
    private let themeProvider: ArtworkThemeProviding
    private let nowPlayingInfoCenter: NowPlayingInfoCenterUpdating
    private let remoteCommandCenter: RemoteCommandCenterHandling
    private let lockScreenArtworkProvider: LockScreenArtworkProviding
    private let queueManager: QueueManager
    private let offlinePlaybackIndex: LocalPlaybackIndexing?
    private let opportunisticCacher: OfflineOpportunisticCaching?
    private let offlineDownloadQueue: OfflineDownloadQueuing?
    private let diagnostics: DiagnosticsLogging
    private var currentThemeAlbumKey: String?
    private var currentLockScreenAlbumKey: String?
    private var currentLockScreenArtwork: UIImage?
    private var remoteCommandsConfigured = false
    private var lastOfflineTrackEventKey: String?
    private var hasPrimedEngineFromQueue = false
    private var metadataSequence: UInt64 = 0
    private var scenePhaseObserver: NSObjectProtocol?
    private var upNextRefreshWork: DispatchWorkItem?
    private var engineQueueStale = false
    private static let upNextWindowSize = 100

    typealias PlaybackEngineFactory = (URL, String) -> PlaybackEngineing

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        libraryServiceFactory: @escaping PlexLibraryServiceFactory = { serverURL, token in
            let config = PlexDefaults.configuration()
            let builder = PlexLibraryRequestBuilder(baseURL: serverURL, token: token, configuration: config)
            return PlexLibraryService(
                httpClient: PlexHTTPClient(),
                requestBuilder: builder,
                paginator: PlexPaginator(pageSize: 50)
            )
        },
        engineFactory: @escaping PlaybackEngineFactory = PlaybackViewModel.defaultEngineFactory,
        themeProvider: ArtworkThemeProviding = ArtworkThemeProvider.shared,
        nowPlayingInfoCenter: NowPlayingInfoCenterUpdating = NowPlayingInfoCenterUpdater(),
        remoteCommandCenter: RemoteCommandCenterHandling = RemoteCommandCenterHandler(),
        lockScreenArtworkProvider: LockScreenArtworkProviding = LockScreenArtworkProvider(),
        queueManager: QueueManager? = nil,
        offlinePlaybackIndex: LocalPlaybackIndexing? = OfflineServices.shared.playbackIndex,
        opportunisticCacher: OfflineOpportunisticCaching? = OfflineServices.shared.coordinator,
        offlineDownloadQueue: OfflineDownloadQueuing? = OfflineServices.shared.coordinator,
        diagnostics: DiagnosticsLogging = DiagnosticsLogger.shared
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.engineFactory = engineFactory
        self.themeProvider = themeProvider
        self.nowPlayingInfoCenter = nowPlayingInfoCenter
        self.remoteCommandCenter = remoteCommandCenter
        self.lockScreenArtworkProvider = lockScreenArtworkProvider
        self.queueManager = queueManager ?? QueueManager()
        self.bypassAuthChecks = false
        self.offlinePlaybackIndex = offlinePlaybackIndex
        self.opportunisticCacher = opportunisticCacher
        self.offlineDownloadQueue = offlineDownloadQueue
        self.diagnostics = diagnostics
        restoreQueueSnapshotIfAvailable()
        observeScenePhase()
    }

    init(
        engine: PlaybackEngineing,
        themeProvider: ArtworkThemeProviding = ArtworkThemeProvider.shared,
        nowPlayingInfoCenter: NowPlayingInfoCenterUpdating = NowPlayingInfoCenterUpdater(),
        remoteCommandCenter: RemoteCommandCenterHandling = RemoteCommandCenterHandler(),
        lockScreenArtworkProvider: LockScreenArtworkProviding = LockScreenArtworkProvider(),
        queueManager: QueueManager? = nil,
        offlinePlaybackIndex: LocalPlaybackIndexing? = nil,
        opportunisticCacher: OfflineOpportunisticCaching? = nil,
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        libraryServiceFactory: @escaping PlexLibraryServiceFactory = { serverURL, token in
            let config = PlexDefaults.configuration()
            let builder = PlexLibraryRequestBuilder(baseURL: serverURL, token: token, configuration: config)
            return PlexLibraryService(
                httpClient: PlexHTTPClient(),
                requestBuilder: builder,
                paginator: PlexPaginator(pageSize: 50)
            )
        },
        offlineDownloadQueue: OfflineDownloadQueuing? = nil,
        diagnostics: DiagnosticsLogging = DiagnosticsLogger.shared
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.engineFactory = PlaybackViewModel.defaultEngineFactory
        self.engine = engine
        self.bypassAuthChecks = true
        self.themeProvider = themeProvider
        self.nowPlayingInfoCenter = nowPlayingInfoCenter
        self.remoteCommandCenter = remoteCommandCenter
        self.lockScreenArtworkProvider = lockScreenArtworkProvider
        self.queueManager = queueManager ?? QueueManager()
        self.offlinePlaybackIndex = offlinePlaybackIndex
        self.opportunisticCacher = opportunisticCacher
        self.offlineDownloadQueue = offlineDownloadQueue
        self.diagnostics = diagnostics
        bindEngineCallbacks()
        restoreQueueSnapshotIfAvailable()
        observeScenePhase()
    }

    deinit {
        if let scenePhaseObserver {
            NotificationCenter.default.removeObserver(scenePhaseObserver)
        }
    }

    func play(tracks: [PlexTrack], startIndex: Int, context: NowPlayingContext?) {
        errorMessage = nil
        setNowPlayingContext(context)
        if bypassAuthChecks {
            engine?.play(tracks: tracks, startIndex: startIndex)
            persistQueueStateFromPlaybackStart(tracks: tracks, startIndex: startIndex, context: context)
            return
        }
        guard let serverURL = serverStore.serverURL else {
            errorMessage = "Missing server URL."
            return
        }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else {
            errorMessage = "Missing auth token."
            return
        }
        if engine == nil || lastServerURL != serverURL || lastToken != token {
            engine = engineFactory(serverURL, token)
            lastServerURL = serverURL
            lastToken = token
            bindEngineCallbacks()
        }
        engine?.play(tracks: tracks, startIndex: startIndex)
        persistQueueStateFromPlaybackStart(tracks: tracks, startIndex: startIndex, context: context)
        hasPrimedEngineFromQueue = true
        refreshUpNextTracks()
    }

    func togglePlayPause() {
        if hasPrimedEngineFromQueue == false, let nowPlaying {
            let snapshot = queueManager.snapshot()
            if !snapshot.entries.isEmpty {
                let tracks = snapshot.entries.map(\.track)
                let context = nowPlayingContext ?? makeContext(from: snapshot)
                play(tracks: tracks, startIndex: snapshot.currentIndex ?? 0, context: context)
                if snapshot.elapsedTime > 0 {
                    engine?.seek(to: snapshot.elapsedTime)
                }
                if nowPlaying.isPlaying == false {
                    engine?.togglePlayPause()
                }
                hasPrimedEngineFromQueue = true
                return
            }
        }
        engine?.togglePlayPause()
    }

    func stop() {
        engine?.stop()
        Task {
            _ = await queueManager.setState(QueueState(entries: [], currentIndex: nil, elapsedTime: 0, isPlaying: false))
        }
        nowPlaying = nil
        nowPlayingContext = nil
        albumTheme = nil
        upNextTracks = []
        currentThemeAlbumKey = nil
        currentLockScreenAlbumKey = nil
        currentLockScreenArtwork = nil
        nowPlayingInfoCenter.clear()
        if remoteCommandsConfigured {
            remoteCommandCenter.teardown()
            remoteCommandsConfigured = false
        }
        lastOfflineTrackEventKey = nil
        hasPrimedEngineFromQueue = false
    }

    func skipToNext() {
        refreshEngineQueueIfStale(currentIndex: nowPlaying?.queueIndex)
        engine?.skipToNext()
    }

    func skipToPrevious() {
        refreshEngineQueueIfStale(currentIndex: nowPlaying?.queueIndex)
        engine?.skipToPrevious()
    }

    func seek(to seconds: TimeInterval) {
        engine?.seek(to: seconds)
    }

    func enqueue(mode: QueueInsertMode, tracks: [PlexTrack], context: NowPlayingContext?) {
        Task {
            await insertIntoQueue(
                mode: mode,
                tracks: tracks,
                context: context,
                signature: "enqueue:\(tracks.map(\.ratingKey).joined(separator: ",")):\(mode.rawValue)"
            )
        }
    }

    func queueAlbumDownload(album: PlexAlbum, albumRatingKeys: [String]) async throws {
        let keys = albumRatingKeys.isEmpty ? [album.ratingKey] : albumRatingKeys
        do {
            try await offlineDownloadQueue?.enqueueAlbumDownload(
                albumIdentity: OfflineAlbumIdentity.make(for: album),
                displayTitle: album.title,
                artistName: album.artist,
                artworkPath: album.thumb ?? album.art,
                albumRatingKeys: keys,
                source: .explicitAlbum
            )
        } catch {
            errorMessage = "Failed to queue album download."
            throw error
        }
    }

    func downloadAlbum(album: PlexAlbum, albumRatingKeys: [String]) {
        Task {
            _ = try? await queueAlbumDownload(album: album, albumRatingKeys: albumRatingKeys)
        }
    }

    func downloadCollection(collection: PlexCollection, sectionKey: String) {
        Task {
            do {
                guard sectionKey.isEmpty == false else {
                    throw OfflineRuntimeError.missingServerURL
                }
                guard let serverURL = serverStore.serverURL else {
                    throw OfflineRuntimeError.missingServerURL
                }
                let storedToken = try tokenStore.load()
                guard let token = storedToken else {
                    throw OfflineRuntimeError.missingAuthToken
                }
                let service = libraryServiceFactory(serverURL, token)
                let albums = try await service.fetchAlbumsInCollection(
                    sectionId: sectionKey,
                    collectionKey: collection.ratingKey
                )
                let groups = makeCollectionAlbumGroups(from: albums)
                try await offlineDownloadQueue?.reconcileCollectionDownload(
                    collectionKey: collection.ratingKey,
                    title: collection.title,
                    albumGroups: groups
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to queue collection download."
                }
            }
        }
    }

    func enqueueAlbum(mode: QueueInsertMode, album: PlexAlbum, albumRatingKeys: [String]) {
        Task {
            do {
                let ratingKeys = albumRatingKeys.isEmpty ? [album.ratingKey] : albumRatingKeys
                let tracks = try await fetchMergedTracksForAlbum(ratingKeys: ratingKeys)
                let context = makeQueueContext(
                    album: album,
                    albumRatingKeys: ratingKeys,
                    tracks: tracks
                )
                await insertIntoQueue(
                    mode: mode,
                    tracks: tracks,
                    context: context,
                    signature: "album:\(ratingKeys.joined(separator: ",")):\(mode.rawValue)"
                )
            } catch {
                if let statusCode = (error as? PlexHTTPError)?.statusCode {
                    errorMessage = "Failed to queue album (HTTP \(statusCode))."
                } else {
                    errorMessage = "Failed to queue album."
                }
            }
        }
    }

    func enqueueTrack(
        mode: QueueInsertMode,
        track: PlexTrack,
        album: PlexAlbum,
        albumRatingKeys: [String],
        allTracks: [PlexTrack],
        artworkRequest: ArtworkRequest?
    ) {
        let context = NowPlayingContext(
            album: album,
            albumRatingKeys: albumRatingKeys.isEmpty ? [album.ratingKey] : albumRatingKeys,
            tracks: allTracks,
            artworkRequest: artworkRequest
        )
        Task {
            await insertIntoQueue(
                mode: mode,
                tracks: [track],
                context: context,
                signature: "track:\(track.ratingKey):\(mode.rawValue)"
            )
        }
    }

    func clearUpcomingQueue() {
        Task {
            let previous = queueManager.snapshot()
            let updated = await queueManager.clearUpcoming()
            await applyQueueMutation(updated: updated, previous: previous)
        }
    }

    func removeUpcomingQueueItem(atAbsoluteIndex index: Int) {
        Task {
            guard let entry = queueManager.entry(at: index) else { return }
            let previous = queueManager.snapshot()
            let updated = await queueManager.removeUpcoming(entryID: entry.id)
            await applyQueueMutation(updated: updated, previous: previous)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func selectUpNextTrack(_ track: PlexTrack) {
        let snapshot = queueManager.snapshot()
        guard let index = snapshot.entries.firstIndex(where: { $0.track.ratingKey == track.ratingKey }) else {
            return
        }
        let tracks = snapshot.entries.map(\.track)
        let context = makeContext(from: snapshot)
        play(tracks: tracks, startIndex: index, context: context)
    }

    private func refreshUpNextTracks() {
        let snapshot = queueManager.snapshot()
        guard let currentIndex = snapshot.currentIndex,
              currentIndex >= 0,
              currentIndex < snapshot.entries.count else {
            upNextTracks = []
            return
        }
        let start = currentIndex + 1
        guard start < snapshot.entries.count else {
            upNextTracks = []
            return
        }
        let end = min(start + Self.upNextWindowSize, snapshot.entries.count)
        upNextTracks = Array(snapshot.entries[start..<end]).map(\.track)
    }

    private func scheduleUpNextRefresh() {
        upNextRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshUpNextTracks()
            }
        }
        upNextRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func refreshEngineQueueIfStale(currentIndex overrideIndex: Int? = nil) {
        guard engineQueueStale else { return }
        engineQueueStale = false
        let snapshot = queueManager.snapshot()
        guard let currentIndex = overrideIndex ?? snapshot.currentIndex else { return }
        let tracks = snapshot.entries.map(\.track)
        engine?.refreshQueue(tracks: tracks, currentIndex: currentIndex)
    }

    private func restoreQueueSnapshotIfAvailable() {
        let snapshot = queueManager.snapshot()
        guard let currentIndex = snapshot.currentIndex,
              currentIndex >= 0,
              currentIndex < snapshot.entries.count else {
            return
        }
        let entry = snapshot.entries[currentIndex]
        let duration = entry.track.duration.map { Double($0) / 1000.0 }
        nowPlaying = NowPlayingState(
            trackRatingKey: entry.track.ratingKey,
            trackTitle: entry.track.title,
            artistName: entry.track.originalTitle ?? entry.track.grandparentTitle,
            isPlaying: false,
            elapsedTime: snapshot.elapsedTime,
            duration: duration,
            queueIndex: currentIndex
        )
        let context = makeContext(from: snapshot)
        setNowPlayingContext(context)
        refreshUpNextTracks()
        configureRemoteCommandsIfNeeded()
        publishLockScreenMetadata(for: nowPlaying!)
    }

    private func persistQueueStateFromPlaybackStart(
        tracks: [PlexTrack],
        startIndex: Int,
        context: NowPlayingContext?
    ) {
        let entries = tracks.map { track in
            QueueEntry(
                track: track,
                album: context?.album,
                albumRatingKeys: context?.albumRatingKeys ?? [],
                artworkRequest: context?.artworkRequest,
                isPlayable: true,
                skipReason: nil
            )
        }
        let clampedIndex = tracks.isEmpty ? nil : min(max(startIndex, 0), max(tracks.count - 1, 0))
        let state = QueueState(
            entries: entries,
            currentIndex: clampedIndex,
            elapsedTime: 0,
            isPlaying: true
        )
        Task {
            _ = await queueManager.setState(state)
        }
    }

    private func fetchMergedTracksForAlbum(ratingKeys: [String]) async throws -> [PlexTrack] {
        guard let serverURL = serverStore.serverURL else {
            throw OfflineRuntimeError.missingServerURL
        }
        let storedToken = try tokenStore.load()
        guard let token = storedToken else {
            throw OfflineRuntimeError.missingAuthToken
        }
        let service = libraryServiceFactory(serverURL, token)
        var combined: [PlexTrack] = []
        try await withThrowingTaskGroup(of: [PlexTrack].self) { group in
            for ratingKey in ratingKeys {
                group.addTask {
                    try await service.fetchTracks(albumRatingKey: ratingKey)
                }
            }
            for try await tracks in group {
                combined.append(contentsOf: tracks)
            }
        }
        return combined.sorted { lhs, rhs in
            let lhsDisc = lhs.parentIndex ?? 0
            let rhsDisc = rhs.parentIndex ?? 0
            if lhsDisc != rhsDisc {
                return lhsDisc < rhsDisc
            }
            let lhsIndex = lhs.index ?? Int.max
            let rhsIndex = rhs.index ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func makeQueueContext(
        album: PlexAlbum,
        albumRatingKeys: [String],
        tracks: [PlexTrack]
    ) -> NowPlayingContext? {
        guard let serverURL = serverStore.serverURL else { return nil }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else { return nil }
        let builder = ArtworkRequestBuilder(baseURL: serverURL, token: token)
        let artworkRequest = builder.albumRequest(for: album, size: .detail)
        return NowPlayingContext(
            album: album,
            albumRatingKeys: albumRatingKeys,
            tracks: tracks,
            artworkRequest: artworkRequest
        )
    }

    private func makeContext(from queue: QueueState) -> NowPlayingContext? {
        guard let currentIndex = queue.currentIndex,
              currentIndex >= 0,
              currentIndex < queue.entries.count else {
            return nil
        }
        let current = queue.entries[currentIndex]
        let tracks = queue.entries.map(\.track)
        guard let album = current.album else {
            return nil
        }
        let artworkBuilder: ArtworkRequestBuilder?
        if let serverURL = serverStore.serverURL,
           let token = (try? tokenStore.load()) ?? nil {
            artworkBuilder = ArtworkRequestBuilder(baseURL: serverURL, token: token)
        } else {
            artworkBuilder = nil
        }
        let albumsByRatingKey = queue.entries.reduce(into: [String: PlexAlbum]()) { partialResult, entry in
            guard let album = entry.album else { return }
            partialResult[album.ratingKey] = album
        }
        let artworkRequestsByAlbumKey = queue.entries.reduce(into: [String: ArtworkRequest]()) { partialResult, entry in
            guard let album = entry.album else { return }
            if let fallbackRequest = artworkBuilder?.albumRequest(for: album, size: .detail) {
                partialResult[album.ratingKey] = fallbackRequest
            }
        }
        let artworkRequest = artworkRequestsByAlbumKey[album.ratingKey]
            ?? artworkBuilder?.albumRequest(for: album, size: .detail)
        return NowPlayingContext(
            album: album,
            albumRatingKeys: current.albumRatingKeys.isEmpty ? [album.ratingKey] : current.albumRatingKeys,
            tracks: tracks,
            artworkRequest: artworkRequest,
            albumsByRatingKey: albumsByRatingKey.isEmpty ? nil : albumsByRatingKey,
            artworkRequestsByAlbumKey: artworkRequestsByAlbumKey.isEmpty ? nil : artworkRequestsByAlbumKey
        )
    }

    private func insertIntoQueue(
        mode: QueueInsertMode,
        tracks: [PlexTrack],
        context: NowPlayingContext?,
        signature: String
    ) async {
        let entries = tracks.map { track in
            QueueEntry(
                track: track,
                album: context?.album,
                albumRatingKeys: context?.albumRatingKeys ?? [],
                artworkRequest: context?.artworkRequest,
                isPlayable: isTrackPlayable(track),
                skipReason: isTrackPlayable(track) ? nil : .missingPlaybackSource
            )
        }
        let previous = queueManager.snapshot()
        let result = await queueManager.insert(
            QueueInsertRequest(
                mode: mode,
                entries: entries,
                signature: signature,
                requestedAt: Date()
            )
        )
        if result.duplicateBlocked {
            errorMessage = "Queue cue: we heard you already."
            return
        }
        if result.insertedCount == 0 {
            errorMessage = queueErrorMessageForSkipped(result.skipped)
            return
        }
        if !result.skipped.isEmpty {
            errorMessage = queuePartialMessage(inserted: result.insertedCount, skipped: result.skipped)
        }
        await applyQueueMutation(updated: result.state, previous: previous)
    }

    private func applyQueueMutation(updated: QueueState, previous: QueueState) async {
        guard let currentIndex = updated.currentIndex, !updated.entries.isEmpty else {
            return
        }

        // Tail-only append: currentIndex unchanged, entries only grew at the end.
        // Skip expensive context rebuild and engine refresh — just update Up Next.
        let isTailAppend = previous.currentIndex == currentIndex
            && nowPlaying != nil
            && updated.entries.count > previous.entries.count
            && !previous.entries.isEmpty
            && updated.entries[previous.entries.count - 1].id == previous.entries[previous.entries.count - 1].id
        if isTailAppend {
            scheduleUpNextRefresh()
            engineQueueStale = true
            return
        }

        if previous.currentIndex == currentIndex, nowPlaying != nil {
            let context = makeContext(from: updated)
            let tracks = updated.entries.map(\.track)
            setNowPlayingContext(context)
            engine?.refreshQueue(tracks: tracks, currentIndex: currentIndex)
            refreshUpNextTracks()
            return
        }
        let context = makeContext(from: updated)
        let tracks = updated.entries.map(\.track)
        let shouldRestoreElapsed = previous.currentIndex == currentIndex
        let elapsed = shouldRestoreElapsed ? previous.elapsedTime : 0
        play(tracks: tracks, startIndex: currentIndex, context: context)
        if elapsed > 0 {
            engine?.seek(to: elapsed)
        }
        if previous.isPlaying == false || updated.isPlaying == false {
            engine?.togglePlayPause()
        }
        refreshUpNextTracks()
    }

    private func isTrackPlayable(_ track: PlexTrack) -> Bool {
        guard let media = track.media else { return false }
        return media.contains { !$0.parts.isEmpty }
    }

    private func queuePartialMessage(inserted: Int, skipped: [QueueInsertSkipReason]) -> String {
        let groups = Dictionary(grouping: skipped, by: { $0 }).mapValues(\.count)
        let details = groups
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value) \($0.key.rawValue)" }
            .joined(separator: ", ")
        return "Queued \(inserted) track\(inserted == 1 ? "" : "s"), skipped \(skipped.count) (\(details))."
    }

    private func queueErrorMessageForSkipped(_ skipped: [QueueInsertSkipReason]) -> String {
        guard !skipped.isEmpty else { return "Failed to queue tracks." }
        let details = Dictionary(grouping: skipped, by: { $0 }).mapValues(\.count)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value) \($0.key.rawValue)" }
            .joined(separator: ", ")
        return "No playable tracks were queued (\(details))."
    }

    private func bindEngineCallbacks() {
        engine?.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.handleStateChange(state)
            }
        }
        engine?.onError = { [weak self] error in
            self?.errorMessage = error.message
        }
    }

    private func handleStateChange(_ state: NowPlayingState?) {
        if let state {
            diagnostics.log(.playbackStateChange(trackKey: state.trackRatingKey, isPlaying: state.isPlaying))
            diagnostics.log(.playbackUISync(trackKey: state.trackRatingKey))
        }
        let previousIndex = nowPlaying?.queueIndex
        nowPlaying = state
        if let state, state.queueIndex != previousIndex {
            refreshUpNextTracks()
            refreshEngineQueueIfStale(currentIndex: state.queueIndex)
        }
        guard let state else {
            currentLockScreenAlbumKey = nil
            currentLockScreenArtwork = nil
            nowPlayingInfoCenter.clear()
            if remoteCommandsConfigured {
                remoteCommandCenter.teardown()
                remoteCommandsConfigured = false
            }
            return
        }
        Task {
            _ = await queueManager.updatePlayback(
                currentIndex: state.queueIndex,
                elapsedTime: state.elapsedTime,
                isPlaying: state.isPlaying
            )
        }
        configureRemoteCommandsIfNeeded()
        handleOfflineStateHooks(for: state)
        guard let context = nowPlayingContext else {
            publishLockScreenMetadata(for: state)
            return
        }
        let track: PlexTrack?
        if let queueIndex = state.queueIndex, queueIndex >= 0, queueIndex < context.tracks.count {
            track = context.tracks[queueIndex]
        } else {
            track = context.tracks.first(where: { $0.ratingKey == state.trackRatingKey })
        }
        guard let track else { return }
        guard let albumKey = track.parentRatingKey else { return }
        let queueSnapshot = queueManager.snapshot()
        let fallbackEntry: QueueEntry? = {
            guard let queueIndex = state.queueIndex,
                  queueIndex >= 0,
                  queueIndex < queueSnapshot.entries.count else {
                return nil
            }
            return queueSnapshot.entries[queueIndex]
        }()
        let albumsByRatingKey = context.albumsByRatingKey
            ?? queueSnapshot.entries.reduce(into: [String: PlexAlbum]()) { partialResult, entry in
                guard let album = entry.album else { return }
                partialResult[album.ratingKey] = album
            }
        guard let album = albumsByRatingKey[albumKey] ?? fallbackEntry?.album else {
            publishLockScreenMetadata(for: state)
            return
        }
        if album.ratingKey == context.album.ratingKey {
            publishLockScreenMetadata(for: state)
            return
        }
        let fallbackArtworkRequests = queueSnapshot.entries.reduce(into: [String: ArtworkRequest]()) { partialResult, entry in
            guard let album = entry.album else { return }
            if let serverURL = serverStore.serverURL,
               let token = (try? tokenStore.load()) ?? nil,
               let request = ArtworkRequestBuilder(baseURL: serverURL, token: token).albumRequest(for: album, size: .detail) {
                partialResult[album.ratingKey] = request
            }
        }
        let artworkRequest = context.artworkRequestsByAlbumKey?[album.ratingKey]
            ?? fallbackArtworkRequests[album.ratingKey]
            ?? context.artworkRequest
        let updatedContext = NowPlayingContext(
            album: album,
            albumRatingKeys: [album.ratingKey],
            tracks: context.tracks,
            artworkRequest: artworkRequest,
            albumsByRatingKey: albumsByRatingKey.isEmpty ? nil : albumsByRatingKey,
            artworkRequestsByAlbumKey: (context.artworkRequestsByAlbumKey ?? fallbackArtworkRequests).isEmpty
                ? nil
                : (context.artworkRequestsByAlbumKey ?? fallbackArtworkRequests)
        )
        setNowPlayingContext(updatedContext)
        publishLockScreenMetadata(for: state)
    }

    private func setNowPlayingContext(_ context: NowPlayingContext?) {
        nowPlayingContext = context
        guard let context else {
            albumTheme = nil
            currentThemeAlbumKey = nil
            currentLockScreenAlbumKey = nil
            currentLockScreenArtwork = nil
            if let state = nowPlaying {
                publishLockScreenMetadata(for: state)
            }
            lastOfflineTrackEventKey = nil
            return
        }
        let albumKey = context.album.ratingKey
        if currentThemeAlbumKey == albumKey {
            return
        }
        currentThemeAlbumKey = albumKey
        Task {
            let theme = await themeProvider.theme(for: context.artworkRequest)
            await MainActor.run {
                if self.currentThemeAlbumKey == albumKey {
                    self.albumTheme = theme
                }
            }
        }

        if currentLockScreenAlbumKey == albumKey {
            return
        }
        currentLockScreenAlbumKey = albumKey
        currentLockScreenArtwork = nil
        metadataSequence &+= 1
        let capturedSequence = metadataSequence
        if let state = nowPlaying {
            publishLockScreenMetadata(for: state)
        }
        Task {
            let artworkImage = await lockScreenArtworkProvider.resolveArtwork(for: context.artworkRequest)
            await MainActor.run {
                guard self.metadataSequence == capturedSequence else { return }
                if self.currentLockScreenAlbumKey == albumKey {
                    self.currentLockScreenArtwork = artworkImage
                    if let state = self.nowPlaying {
                        self.publishLockScreenMetadata(for: state)
                    }
                }
            }
        }
    }

    private func handleOfflineStateHooks(for state: NowPlayingState) {
        guard lastOfflineTrackEventKey != state.trackRatingKey else { return }
        lastOfflineTrackEventKey = state.trackRatingKey
        offlinePlaybackIndex?.markPlayed(trackKey: state.trackRatingKey, at: Date())

        guard let context = nowPlayingContext else {
            return
        }
        let index: Int
        if let queueIndex = state.queueIndex, queueIndex >= 0, queueIndex < context.tracks.count {
            index = queueIndex
        } else if let resolved = context.tracks.firstIndex(where: { $0.ratingKey == state.trackRatingKey }) {
            index = resolved
        } else {
            return
        }
        let current = context.tracks[index]
        let upcoming = Array(context.tracks.dropFirst(index + 1))
        Task {
            await opportunisticCacher?.enqueueOpportunistic(current: current, upcoming: upcoming, limit: 5)
        }
    }

    private func configureRemoteCommandsIfNeeded() {
        guard remoteCommandsConfigured == false else { return }
        remoteCommandsConfigured = true
        remoteCommandCenter.configure(
            handlers: RemoteCommandHandlers(
                onPlay: { [weak self] in
                    Task { @MainActor in
                        self?.diagnostics.log(.remoteCommand(command: "play"))
                        self?.togglePlayPause()
                    }
                },
                onPause: { [weak self] in
                    Task { @MainActor in
                        self?.diagnostics.log(.remoteCommand(command: "pause"))
                        self?.togglePlayPause()
                    }
                },
                onNext: { [weak self] in
                    Task { @MainActor in
                        self?.diagnostics.log(.remoteCommand(command: "next"))
                        self?.skipToNext()
                    }
                },
                onPrevious: { [weak self] in
                    Task { @MainActor in
                        self?.diagnostics.log(.remoteCommand(command: "previous"))
                        self?.skipToPrevious()
                    }
                }
            )
        )
    }

    private func observeScenePhase() {
        scenePhaseObserver = NotificationCenter.default.addObserver(
            forName: .lunaraScenePhaseDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let phase = notification.userInfo?["phase"] as? String ?? "unknown"
            Task { @MainActor in
                self.handleScenePhaseChange(phase: phase)
            }
        }
    }

    private func handleScenePhaseChange(phase: String) {
        diagnostics.log(.scenePhaseChange(phase: phase))
        switch phase {
        case "background":
            queueManager.persistImmediately()
            guard let state = nowPlaying else { return }
            publishLockScreenMetadata(for: state)
        case "active":
            guard let state = nowPlaying else { return }
            publishLockScreenMetadata(for: state)
        default:
            break
        }
    }

    private func publishLockScreenMetadata(for state: NowPlayingState) {
        let metadata = LockScreenNowPlayingMetadata(
            title: state.trackTitle,
            artist: state.artistName,
            albumTitle: nowPlayingContext?.album.title,
            elapsedTime: state.elapsedTime,
            duration: state.duration,
            isPlaying: state.isPlaying,
            artworkImage: currentLockScreenArtwork
        )
        nowPlayingInfoCenter.update(with: metadata)
    }

    private static func defaultEngineFactory(serverURL: URL, token: String) -> PlaybackEngineing {
        let config = PlexDefaults.configuration()
        let builder = PlexPlaybackURLBuilder(baseURL: serverURL, token: token, configuration: config)
        let resolver = PlaybackSourceResolver(
            localIndex: OfflineServices.shared.playbackIndex,
            urlBuilder: builder,
            networkMonitor: NetworkReachabilityMonitor.shared
        )
        return PlaybackEngine(
            sourceResolver: resolver,
            fallbackURLBuilder: builder,
            audioSession: AudioSessionManager()
        )
    }

    private func makeCollectionAlbumGroups(from albums: [PlexAlbum]) -> [OfflineCollectionAlbumGroup] {
        var groups: [String: [PlexAlbum]] = [:]
        for album in albums {
            groups[OfflineAlbumIdentity.make(for: album), default: []].append(album)
        }

        return groups.values.compactMap { groupedAlbums in
            guard let first = groupedAlbums.first else { return nil }
            return OfflineCollectionAlbumGroup(
                albumIdentity: OfflineAlbumIdentity.make(for: first),
                displayTitle: first.title,
                artistName: first.artist,
                artworkPath: first.thumb ?? first.art,
                albumRatingKeys: groupedAlbums.map(\.ratingKey).sorted()
            )
        }
        .sorted { lhs, rhs in
            lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
    }
}
