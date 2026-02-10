import Foundation
import Combine
import SwiftUI

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    @Published var tracks: [PlexTrack] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let album: PlexAlbum
    private let albumRatingKeys: [String]
    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void
    private let playbackController: PlaybackControlling

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
        playbackController: PlaybackControlling? = nil
    ) {
        self.album = album
        self.albumRatingKeys = albumRatingKeys
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.sessionInvalidationHandler = sessionInvalidationHandler
        self.playbackController = playbackController ?? PlaybackNoopController()
    }

    func loadTracks() async {
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
        } catch {
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
        playbackController.play(tracks: tracks, startIndex: 0)
    }

    func playTrack(_ track: PlexTrack) {
        guard let index = tracks.firstIndex(where: { $0.ratingKey == track.ratingKey }) else { return }
        playbackController.play(tracks: tracks, startIndex: index)
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
}
