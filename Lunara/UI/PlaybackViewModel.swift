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
    private let engineFactory: PlaybackEngineFactory
    private var engine: PlaybackEngineing?
    private var lastServerURL: URL?
    private var lastToken: String?
    private let bypassAuthChecks: Bool
    private let themeProvider: ArtworkThemeProviding
    private var currentThemeAlbumKey: String?

    typealias PlaybackEngineFactory = (URL, String) -> PlaybackEngineing

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        engineFactory: @escaping PlaybackEngineFactory = PlaybackViewModel.defaultEngineFactory,
        themeProvider: ArtworkThemeProviding = ArtworkThemeProvider.shared
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.engineFactory = engineFactory
        self.themeProvider = themeProvider
        self.bypassAuthChecks = false
    }

    init(engine: PlaybackEngineing, themeProvider: ArtworkThemeProviding = ArtworkThemeProvider.shared) {
        self.tokenStore = PlexAuthTokenStore(keychain: KeychainStore())
        self.serverStore = UserDefaultsServerAddressStore()
        self.engineFactory = PlaybackViewModel.defaultEngineFactory
        self.engine = engine
        self.bypassAuthChecks = true
        self.themeProvider = themeProvider
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

    private static func defaultEngineFactory(serverURL: URL, token: String) -> PlaybackEngineing {
        let config = PlexDefaults.configuration()
        let builder = PlexPlaybackURLBuilder(baseURL: serverURL, token: token, configuration: config)
        let resolver = PlaybackSourceResolver(localIndex: nil, urlBuilder: builder)
        return PlaybackEngine(
            sourceResolver: resolver,
            fallbackURLBuilder: builder,
            audioSession: AudioSessionManager()
        )
    }
}
