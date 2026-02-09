import Foundation
import Combine
import SwiftUI

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    @Published var tracks: [PlexTrack] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let album: PlexAlbum
    private let tokenStore: PlexAuthTokenStore

    init(album: PlexAlbum, tokenStore: PlexAuthTokenStore = PlexAuthTokenStore(keychain: KeychainStore())) {
        self.album = album
        self.tokenStore = tokenStore
    }

    func loadTracks() async {
        errorMessage = nil
        guard let serverURL = serverURL() else {
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
            let config = PlexDefaults.configuration()
            let builder = PlexLibraryRequestBuilder(baseURL: serverURL, token: token, configuration: config)
            let service = PlexLibraryService(httpClient: PlexHTTPClient(), requestBuilder: builder, paginator: PlexPaginator(pageSize: 50))
            tracks = try await service.fetchTracks(albumRatingKey: album.ratingKey)
        } catch {
            errorMessage = "Failed to load tracks."
        }
    }

    private func serverURL() -> URL? {
        guard let stored = UserDefaults.standard.string(forKey: "plex.server.baseURL") else {
            return nil
        }
        return URL(string: stored)
    }
}
