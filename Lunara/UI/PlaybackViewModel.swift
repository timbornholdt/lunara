import Combine
import Foundation

@MainActor
final class PlaybackViewModel: ObservableObject, PlaybackControlling {
    @Published private(set) var nowPlaying: NowPlayingState?
    @Published private(set) var errorMessage: String?

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let engineFactory: PlaybackEngineFactory
    private var engine: PlaybackEngineing?
    private var lastServerURL: URL?
    private var lastToken: String?
    private let bypassAuthChecks: Bool

    typealias PlaybackEngineFactory = (URL, String) -> PlaybackEngineing

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        engineFactory: @escaping PlaybackEngineFactory = PlaybackViewModel.defaultEngineFactory
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.engineFactory = engineFactory
        self.bypassAuthChecks = false
    }

    init(engine: PlaybackEngineing) {
        self.tokenStore = PlexAuthTokenStore(keychain: KeychainStore())
        self.serverStore = UserDefaultsServerAddressStore()
        self.engineFactory = PlaybackViewModel.defaultEngineFactory
        self.engine = engine
        self.bypassAuthChecks = true
        bindEngineCallbacks()
    }

    func play(tracks: [PlexTrack], startIndex: Int) {
        errorMessage = nil
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
    }

    func clearError() {
        errorMessage = nil
    }

    private func bindEngineCallbacks() {
        engine?.onStateChange = { [weak self] state in
            self?.nowPlaying = state
        }
        engine?.onError = { [weak self] error in
            self?.errorMessage = error.message
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
