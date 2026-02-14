import Foundation
import Combine
import SwiftUI

@MainActor
final class CollectionAlbumsViewModel: ObservableObject {
    @Published var albums: [PlexAlbum] = []
    @Published var marqueeAlbums: [PlexAlbum] = []
    @Published var isLoading = false
    @Published var isPreparingPlayback = false
    @Published var errorMessage: String?

    let collection: PlexCollection

    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void
    private let playbackController: PlaybackControlling
    private let shuffleProvider: ([PlexTrack]) -> [PlexTrack]
    private let marqueeShuffleProvider: ([PlexAlbum]) -> [PlexAlbum]
    private let sectionKey: String
    private let cacheStore: LibraryCacheStoring
    private var albumGroups: [String: [PlexAlbum]] = [:]
    private var hasLoaded = false

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
        sessionInvalidationHandler: @escaping () -> Void = {},
        playbackController: PlaybackControlling? = nil,
        shuffleProvider: @escaping ([PlexTrack]) -> [PlexTrack] = { $0.shuffled() },
        marqueeShuffleProvider: @escaping ([PlexAlbum]) -> [PlexAlbum] = { $0.shuffled() },
        cacheStore: LibraryCacheStoring = LibraryCacheStore()
    ) {
        self.collection = collection
        self.sectionKey = sectionKey
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.sessionInvalidationHandler = sessionInvalidationHandler
        self.playbackController = playbackController ?? PlaybackNoopController()
        self.shuffleProvider = shuffleProvider
        self.marqueeShuffleProvider = marqueeShuffleProvider
        self.cacheStore = cacheStore
    }

    func loadAlbums() async {
        guard !hasLoaded else { return }
        errorMessage = nil
        let cacheKey = LibraryCacheKey.collectionAlbums(collection.ratingKey)
        if let cached = cacheStore.load(key: cacheKey, as: [PlexAlbum].self), !cached.isEmpty {
            albumGroups = Dictionary(grouping: cached, by: albumDedupKey(for:))
            albums = dedupeAlbums(cached)
            if marqueeAlbums.isEmpty {
                marqueeAlbums = marqueeShuffleProvider(albums)
            }
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
            cacheStore.save(key: .collectionAlbums(collection.ratingKey), value: fetchedAlbums)
            if marqueeAlbums.isEmpty {
                marqueeAlbums = marqueeShuffleProvider(albums)
            }
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
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

    func playCollection(shuffled: Bool) async {
        guard isPreparingPlayback == false else { return }
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

        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        do {
            let service = libraryServiceFactory(serverURL, token)
            var combinedTracks: [PlexTrack] = []
            var seenTrackKeys = Set<String>()
            for album in albums {
                let keys = ratingKeys(for: album)
                for key in keys {
                    let fetchedTracks = try await service.fetchTracks(albumRatingKey: key)
                    let sortedTracks = sortTracks(fetchedTracks)
                    for track in sortedTracks where seenTrackKeys.insert(track.ratingKey).inserted {
                        combinedTracks.append(track)
                    }
                }
            }
            guard combinedTracks.isEmpty == false else {
                errorMessage = "No tracks found in this collection."
                return
            }

            let tracks = shuffled ? shuffleProvider(combinedTracks) : combinedTracks
            playbackController.play(
                tracks: tracks,
                startIndex: 0,
                context: makeNowPlayingContext(
                    tracks: tracks,
                    serverURL: serverURL,
                    token: token
                )
            )
        } catch {
            guard !Task.isCancelled else { return }
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                errorMessage = "Failed to load collection tracks."
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

    private func sortTracks(_ tracks: [PlexTrack]) -> [PlexTrack] {
        tracks.sorted { lhs, rhs in
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

    private func makeNowPlayingContext(
        tracks: [PlexTrack],
        serverURL: URL,
        token: String
    ) -> NowPlayingContext? {
        guard let primaryAlbum = albumForContext(tracks: tracks) ?? albums.first else {
            return nil
        }
        let builder = ArtworkRequestBuilder(baseURL: serverURL, token: token)
        let artworkByAlbumKey = albums.reduce(into: [String: ArtworkRequest]()) { result, album in
            let request = builder.albumRequest(for: album, size: .detail)
            for key in ratingKeys(for: album) {
                if let request {
                    result[key] = request
                }
            }
        }
        let albumMap = albums.reduce(into: [String: PlexAlbum]()) { result, album in
            for key in ratingKeys(for: album) {
                result[key] = album
            }
        }
        let primaryArtwork = artworkByAlbumKey[primaryAlbum.ratingKey]
            ?? builder.albumRequest(for: primaryAlbum, size: .detail)
        return NowPlayingContext(
            album: primaryAlbum,
            albumRatingKeys: ratingKeys(for: primaryAlbum),
            tracks: tracks,
            artworkRequest: primaryArtwork,
            albumsByRatingKey: albumMap.isEmpty ? nil : albumMap,
            artworkRequestsByAlbumKey: artworkByAlbumKey.isEmpty ? nil : artworkByAlbumKey
        )
    }

    private func albumForContext(tracks: [PlexTrack]) -> PlexAlbum? {
        guard let parentKey = tracks.first?.parentRatingKey else { return nil }
        return albums.first { ratingKeys(for: $0).contains(parentKey) }
    }
}
