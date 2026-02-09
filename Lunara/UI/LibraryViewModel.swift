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

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private var selectionStore: PlexLibrarySelectionStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        selectionStore: PlexLibrarySelectionStoring = UserDefaultsLibrarySelectionStore(),
        libraryServiceFactory: @escaping PlexLibraryServiceFactory = { serverURL, token in
            let config = PlexDefaults.configuration()
            let builder = PlexLibraryRequestBuilder(baseURL: serverURL, token: token, configuration: config)
            return PlexLibraryService(
                httpClient: PlexHTTPClient(),
                requestBuilder: builder,
                paginator: PlexPaginator(pageSize: 50)
            )
        },
        sessionInvalidationHandler: @escaping () -> Void = {}
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.selectionStore = selectionStore
        self.libraryServiceFactory = libraryServiceFactory
        self.sessionInvalidationHandler = sessionInvalidationHandler
    }

    func loadSections() async {
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
            let fetched = try await service.fetchLibrarySections()
            sections = fetched.filter { $0.type == "artist" || $0.type == "music" }
            if let storedKey = selectionStore.selectedSectionKey,
               let storedSection = sections.first(where: { $0.key == storedKey }) {
                selectedSection = storedSection
            } else if selectedSection == nil {
                selectedSection = sections.first
            }
            if let selectedSection {
                selectionStore.selectedSectionKey = selectedSection.key
            }
            if let selected = selectedSection {
                try await loadAlbums(section: selected)
            }
        } catch {
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                errorMessage = "Failed to load libraries."
            }
        }
    }

    func selectSection(_ section: PlexLibrarySection) async {
        selectedSection = section
        selectionStore.selectedSectionKey = section.key
        do {
            try await loadAlbums(section: section)
        } catch {
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                errorMessage = "Failed to load albums."
            }
        }
    }

    private func loadAlbums(section: PlexLibrarySection) async throws {
        guard let serverURL = serverStore.serverURL else { return }
        let storedToken = try? tokenStore.load()
        guard let token = storedToken ?? nil else { return }
        let service = libraryServiceFactory(serverURL, token)
        albums = try await service.fetchAlbums(sectionId: section.key)
    }
}
