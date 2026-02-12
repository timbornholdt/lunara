import Foundation

final class AppOfflineTrackFetcher: OfflineTrackFetching {
    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory

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
        }
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
    }

    func fetchMergedTracks(albumRatingKeys: [String]) async throws -> [PlexTrack] {
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
            for key in albumRatingKeys {
                group.addTask {
                    try await service.fetchTracks(albumRatingKey: key)
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
