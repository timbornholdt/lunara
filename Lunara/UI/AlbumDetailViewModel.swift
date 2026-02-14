import Foundation
import Combine
import SwiftUI

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    @Published var tracks: [PlexTrack] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var albumDownloadProgress: OfflineAlbumDownloadProgress?

    private let album: PlexAlbum
    private let albumRatingKeys: [String]
    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void
    private let playbackController: PlaybackControlling
    private let downloadStatusProvider: OfflineDownloadStatusProviding?
    private let cacheStore: LibraryCacheStoring
    private var cancellables: Set<AnyCancellable> = []
    private var hasLoaded = false

    init(
        album: PlexAlbum,
        albumRatingKeys: [String] = [],
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
        sessionInvalidationHandler: @escaping () -> Void = {},
        playbackController: PlaybackControlling? = nil,
        downloadStatusProvider: OfflineDownloadStatusProviding? = OfflineServices.shared.coordinator,
        cacheStore: LibraryCacheStoring = LibraryCacheStore()
    ) {
        self.album = album
        self.albumRatingKeys = albumRatingKeys
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.sessionInvalidationHandler = sessionInvalidationHandler
        self.playbackController = playbackController ?? PlaybackNoopController()
        self.downloadStatusProvider = downloadStatusProvider
        self.cacheStore = cacheStore
        NotificationCenter.default.publisher(for: .offlineDownloadsDidChange)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.refreshDownloadProgress()
                }
            }
            .store(in: &cancellables)
    }

    func loadTracks() async {
        guard !hasLoaded else { return }
        errorMessage = nil
        let cacheKey = LibraryCacheKey.albumTracks(album.ratingKey)
        if let cached = cacheStore.load(key: cacheKey, as: [PlexTrack].self), !cached.isEmpty {
            tracks = cached
            hasLoaded = true
            return
        }
        await refresh()
    }

    func refresh() async {
        errorMessage = nil
        guard let serverURL = serverStore.serverURL else {
            errorMessage = "Missing server URL."
            return
        }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else {
            errorMessage = "Missing auth token."
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let service = libraryServiceFactory(serverURL, token)
            let ratingKeys = albumRatingKeys.isEmpty ? [album.ratingKey] : albumRatingKeys
            tracks = try await fetchMergedTracks(
                service: service,
                ratingKeys: ratingKeys
            )
            cacheStore.save(key: .albumTracks(album.ratingKey), value: tracks)
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                errorMessage = "Failed to load tracks."
            }
        }
    }

    func playAlbum() {
        playbackController.play(
            tracks: tracks,
            startIndex: 0,
            context: makeNowPlayingContext()
        )
    }

    func playTrack(_ track: PlexTrack) {
        guard let index = tracks.firstIndex(where: { $0.ratingKey == track.ratingKey }) else { return }
        playbackController.play(
            tracks: tracks,
            startIndex: index,
            context: makeNowPlayingContext()
        )
    }

    func refreshDownloadProgress() async {
        guard let downloadStatusProvider else {
            albumDownloadProgress = nil
            return
        }
        let identity = OfflineAlbumIdentity.make(for: album)
        albumDownloadProgress = await downloadStatusProvider.albumDownloadProgress(albumIdentity: identity)
    }

    private func fetchMergedTracks(
        service: PlexLibraryServicing,
        ratingKeys: [String]
    ) async throws -> [PlexTrack] {
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

        return mergeTracks(combined)
    }

    private func mergeTracks(_ tracks: [PlexTrack]) -> [PlexTrack] {
        var seen = Set<String>()
        let unique = tracks.filter { seen.insert($0.ratingKey).inserted }
        return unique.sorted { lhs, rhs in
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

    private func makeNowPlayingContext() -> NowPlayingContext? {
        guard let serverURL = serverStore.serverURL else { return nil }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else { return nil }
        let builder = ArtworkRequestBuilder(baseURL: serverURL, token: token)
        let request = builder.albumRequest(for: album, size: .detail)
        let ratingKeys = albumRatingKeys.isEmpty ? [album.ratingKey] : albumRatingKeys
        return NowPlayingContext(
            album: album,
            albumRatingKeys: ratingKeys,
            tracks: tracks,
            artworkRequest: request,
            albumsByRatingKey: [album.ratingKey: album],
            artworkRequestsByAlbumKey: request.map { [album.ratingKey: $0] }
        )
    }
}
