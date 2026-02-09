import Foundation
import Combine
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var sections: [PlexLibrarySection] = []
    @Published var selectedSection: PlexLibrarySection?
    @Published var albums: [PlexAlbum] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let tokenStore: PlexAuthTokenStore

    init(tokenStore: PlexAuthTokenStore = PlexAuthTokenStore(keychain: KeychainStore())) {
        self.tokenStore = tokenStore
    }

    func loadSections() async {
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
            let service = makeService(serverURL: serverURL, token: token)
            let fetched = try await service.fetchLibrarySections()
            sections = fetched.filter { $0.type == "artist" || $0.type == "music" }
            if selectedSection == nil {
                selectedSection = sections.first
            }
            if let selected = selectedSection {
                try await loadAlbums(section: selected)
            }
        } catch {
            errorMessage = "Failed to load libraries."
        }
    }

    func selectSection(_ section: PlexLibrarySection) async {
        selectedSection = section
        do {
            try await loadAlbums(section: section)
        } catch {
            errorMessage = "Failed to load albums."
        }
    }

    private func loadAlbums(section: PlexLibrarySection) async throws {
        guard let serverURL = serverURL() else { return }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else { return }
        let service = makeService(serverURL: serverURL, token: token)
        albums = try await service.fetchAlbums(sectionId: section.key)
    }

    private func serverURL() -> URL? {
        guard let stored = UserDefaults.standard.string(forKey: "plex.server.baseURL") else {
            return nil
        }
        return URL(string: stored)
    }

    private func makeService(serverURL: URL, token: String) -> PlexLibraryService {
        let config = PlexDefaults.configuration()
        let builder = PlexLibraryRequestBuilder(baseURL: serverURL, token: token, configuration: config)
        return PlexLibraryService(httpClient: PlexHTTPClient(), requestBuilder: builder, paginator: PlexPaginator(pageSize: 50))
    }
}
