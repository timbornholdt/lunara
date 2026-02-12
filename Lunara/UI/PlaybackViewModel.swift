import Combine
import Foundation

@MainActor
final class PlaybackViewModel: ObservableObject, PlaybackControlling {
    @Published private(set) var nowPlaying: NowPlayingState?
    @Published private(set) var nowPlayingContext: NowPlayingContext?
    @Published private(set) var albumTheme: AlbumTheme?
    @Published private(set) var errorMessage: String?

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let engineFactory: PlaybackEngineFactory
    private var engine: PlaybackEngineing?
    private var lastServerURL: URL?
    private var lastToken: String?
    private let bypassAuthChecks: Bool
    private let themeProvider: ArtworkThemeProviding
    private let offlinePlaybackIndex: LocalPlaybackIndexing?
    private let opportunisticCacher: OfflineOpportunisticCaching?
    private let offlineDownloadQueue: OfflineDownloadQueuing?
    private var currentThemeAlbumKey: String?
    private var lastOfflineTrackEventKey: String?

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
        offlinePlaybackIndex: LocalPlaybackIndexing? = OfflineServices.shared.playbackIndex,
        opportunisticCacher: OfflineOpportunisticCaching? = OfflineServices.shared.coordinator,
        offlineDownloadQueue: OfflineDownloadQueuing? = OfflineServices.shared.coordinator
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.engineFactory = engineFactory
        self.themeProvider = themeProvider
        self.bypassAuthChecks = false
        self.offlinePlaybackIndex = offlinePlaybackIndex
        self.opportunisticCacher = opportunisticCacher
        self.offlineDownloadQueue = offlineDownloadQueue
    }

    init(
        engine: PlaybackEngineing,
        themeProvider: ArtworkThemeProviding = ArtworkThemeProvider.shared,
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
        offlineDownloadQueue: OfflineDownloadQueuing? = nil
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.engineFactory = PlaybackViewModel.defaultEngineFactory
        self.engine = engine
        self.bypassAuthChecks = true
        self.themeProvider = themeProvider
        self.offlinePlaybackIndex = offlinePlaybackIndex
        self.opportunisticCacher = opportunisticCacher
        self.offlineDownloadQueue = offlineDownloadQueue
        bindEngineCallbacks()
    }

    func play(tracks: [PlexTrack], startIndex: Int, context: NowPlayingContext?) {
        errorMessage = nil
        setNowPlayingContext(context)
        if bypassAuthChecks {
            engine?.play(tracks: tracks, startIndex: startIndex)
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
    }

    func togglePlayPause() {
        engine?.togglePlayPause()
    }

    func stop() {
        engine?.stop()
        nowPlaying = nil
        nowPlayingContext = nil
        albumTheme = nil
        currentThemeAlbumKey = nil
        lastOfflineTrackEventKey = nil
    }

    func skipToNext() {
        engine?.skipToNext()
    }

    func skipToPrevious() {
        engine?.skipToPrevious()
    }

    func seek(to seconds: TimeInterval) {
        engine?.seek(to: seconds)
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

    func clearError() {
        errorMessage = nil
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
        nowPlaying = state
        guard let state else { return }
        handleOfflineStateHooks(for: state)
        guard let context = nowPlayingContext else { return }
        guard let track = context.tracks.first(where: { $0.ratingKey == state.trackRatingKey }) else { return }
        guard let albumKey = track.parentRatingKey else { return }
        guard let albumsByRatingKey = context.albumsByRatingKey,
              let album = albumsByRatingKey[albumKey] else {
            return
        }
        if album.ratingKey == context.album.ratingKey {
            return
        }
        let artworkRequest = context.artworkRequestsByAlbumKey?[album.ratingKey] ?? context.artworkRequest
        let updatedContext = NowPlayingContext(
            album: album,
            albumRatingKeys: [album.ratingKey],
            tracks: context.tracks,
            artworkRequest: artworkRequest,
            albumsByRatingKey: albumsByRatingKey,
            artworkRequestsByAlbumKey: context.artworkRequestsByAlbumKey
        )
        setNowPlayingContext(updatedContext)
    }

    private func setNowPlayingContext(_ context: NowPlayingContext?) {
        nowPlayingContext = context
        guard let context else {
            albumTheme = nil
            currentThemeAlbumKey = nil
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
    }

    private func handleOfflineStateHooks(for state: NowPlayingState) {
        guard lastOfflineTrackEventKey != state.trackRatingKey else { return }
        lastOfflineTrackEventKey = state.trackRatingKey
        offlinePlaybackIndex?.markPlayed(trackKey: state.trackRatingKey, at: Date())

        guard let context = nowPlayingContext,
              let index = context.tracks.firstIndex(where: { $0.ratingKey == state.trackRatingKey }) else {
            return
        }
        let current = context.tracks[index]
        let upcoming = Array(context.tracks.dropFirst(index + 1))
        Task {
            await opportunisticCacher?.enqueueOpportunistic(current: current, upcoming: upcoming, limit: 5)
        }
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
