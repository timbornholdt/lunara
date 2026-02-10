import Foundation
import Combine
import SwiftUI

@MainActor
final class CollectionAlbumsViewModel: ObservableObject {
    @Published var albums: [PlexAlbum] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let collection: PlexCollection

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void
    private let sectionKey: String
    private var albumGroups: [String: [PlexAlbum]] = [:]

    init(
        collection: PlexCollection,
        sectionKey: String = "",
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
        sessionInvalidationHandler: @escaping () -> Void = {}
    ) {
        self.collection = collection
        self.sectionKey = sectionKey
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.sessionInvalidationHandler = sessionInvalidationHandler
    }

    func loadAlbums() async {
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

        guard !sectionKey.isEmpty else {
            errorMessage = "Missing library section."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let service = libraryServiceFactory(serverURL, token)
            let fetchedAlbums = try await service.fetchAlbumsInCollection(
                sectionId: sectionKey,
                collectionKey: collection.ratingKey
            )
            albumGroups = Dictionary(grouping: fetchedAlbums, by: albumDedupKey(for:))
            albums = dedupeAlbums(fetchedAlbums)
        } catch {
            print("CollectionAlbumsViewModel.loadAlbums error: \(error)")
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                if let statusCode = (error as? PlexHTTPError)?.statusCode {
                    errorMessage = "Failed to load collection (HTTP \(statusCode))."
                } else {
                    errorMessage = "Failed to load collection."
                }
            }
        }
    }

    func ratingKeys(for album: PlexAlbum) -> [String] {
        let key = albumDedupKey(for: album)
        let keys = albumGroups[key]?.map(\.ratingKey) ?? [album.ratingKey]
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func dedupeAlbums(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        var seen: [String: Int] = [:]
        var result: [PlexAlbum] = []
        result.reserveCapacity(albums.count)

        for album in albums {
            let identity = albumDedupKey(for: album)
            if let existingIndex = seen[identity] {
                if shouldReplace(existing: result[existingIndex], candidate: album) {
                    result[existingIndex] = album
                }
            } else {
                seen[identity] = result.count
                result.append(album)
            }
        }

        return result
    }

    private func albumDedupKey(for album: PlexAlbum) -> String {
        if let guid = album.guid, !guid.isEmpty {
            return guid
        }
        let title = album.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let year = album.year.map(String.init) ?? ""
        return "\(title)|\(artist)|\(year)"
    }

    private func shouldReplace(existing: PlexAlbum, candidate: PlexAlbum) -> Bool {
        let existingScore = artworkScore(for: existing)
        let candidateScore = artworkScore(for: candidate)
        if candidateScore != existingScore {
            return candidateScore > existingScore
        }
        return false
    }

    private func artworkScore(for album: PlexAlbum) -> Int {
        var score = 0
        if album.art != nil { score += 2 }
        if album.thumb != nil { score += 1 }
        return score
    }
}
