import Foundation
import Combine
import SwiftUI

@MainActor
final class ArtistDetailViewModel: ObservableObject {
    @Published var artist: PlexArtist?
    @Published var albums: [PlexAlbum] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let artistRatingKey: String
    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let libraryServiceFactory: PlexLibraryServiceFactory
    private let sessionInvalidationHandler: () -> Void
    private let playbackController: PlaybackControlling
    private let shuffleProvider: ([PlexTrack]) -> [PlexTrack]

    init(
        artistRatingKey: String,
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
        shuffleProvider: @escaping ([PlexTrack]) -> [PlexTrack] = { $0.shuffled() }
    ) {
        self.artistRatingKey = artistRatingKey
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.libraryServiceFactory = libraryServiceFactory
        self.sessionInvalidationHandler = sessionInvalidationHandler
        self.playbackController = playbackController ?? PlaybackNoopController()
        self.shuffleProvider = shuffleProvider
    }

    func load() async {
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
            print("ArtistDetail.load start ratingKey=\(artistRatingKey)")
            let service = libraryServiceFactory(serverURL, token)
            artist = try await service.fetchArtistDetail(artistRatingKey: artistRatingKey)
            if let artist {
                print("ArtistDetail.load artist title=\(artist.title) ratingKey=\(artist.ratingKey)")
            } else {
                print("ArtistDetail.load artist missing ratingKey=\(artistRatingKey)")
                errorMessage = "Artist not found."
            }
            let fetchedAlbums = try await service.fetchArtistAlbums(artistRatingKey: artistRatingKey)
            let sortedAlbums = sortAlbums(fetchedAlbums)
            var artistTracks: [PlexTrack] = []
            do {
                artistTracks = try await service.fetchArtistTracks(artistRatingKey: artistRatingKey)
            } catch {
                logError(context: "ArtistDetail.loadTracks", error: error)
            }
            var combinedAlbums = sortedAlbums
            if sortedAlbums.contains(where: { $0.duration == nil }), !artistTracks.isEmpty {
                let enriched = enrichAlbumsWithDurations(
                    albums: sortedAlbums,
                    tracks: artistTracks
                )
                combinedAlbums = enriched
            }
            let appearsOn = await loadAppearsOnAlbums(
                tracks: artistTracks,
                existingAlbums: combinedAlbums,
                service: service
            )
            albums = mergeAlbums(primary: combinedAlbums, appearsOn: appearsOn)
            print("ArtistDetail.load albums count=\(albums.count) ratingKey=\(artistRatingKey)")
        } catch {
            logError(context: "ArtistDetail.load", error: error)
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                errorMessage = "Failed to load artist."
            }
        }
    }

    func playAll() async {
        await playTracks(shuffled: false)
    }

    func shuffle() async {
        await playTracks(shuffled: true)
    }

    private func playTracks(shuffled: Bool) async {
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

        do {
            let service = libraryServiceFactory(serverURL, token)
            var tracks = try await service.fetchArtistTracks(artistRatingKey: artistRatingKey)
            if tracks.isEmpty {
                errorMessage = "No tracks found for artist."
                return
            }
            if shuffled {
                tracks = shuffleProvider(tracks)
            } else {
                tracks = orderTracks(tracks, albums: albums)
            }
            let context = makeNowPlayingContext(tracks: tracks, serverURL: serverURL, token: token)
            playbackController.play(tracks: tracks, startIndex: 0, context: context)
        } catch {
            if PlexErrorHelpers.isUnauthorized(error) {
                try? tokenStore.clear()
                sessionInvalidationHandler()
                errorMessage = "Session expired. Please sign in again."
            } else {
                errorMessage = "Failed to load artist tracks."
            }
        }
    }

    private func orderTracks(_ tracks: [PlexTrack], albums: [PlexAlbum]) -> [PlexTrack] {
        let albumYears = albums.reduce(into: [String: Int]()) { result, album in
            if let year = album.year {
                result[album.ratingKey] = year
            }
        }
        return tracks.sorted { lhs, rhs in
            let lhsYear = albumYears[lhs.parentRatingKey ?? ""]
            let rhsYear = albumYears[rhs.parentRatingKey ?? ""]
            if lhsYear != rhsYear {
                switch (lhsYear, rhsYear) {
                case let (.some(a), .some(b)):
                    return a < b
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
            }
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

    private func sortAlbums(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        albums.sorted { lhs, rhs in
            switch (lhs.year, rhs.year) {
            case let (.some(a), .some(b)):
                if a != b { return a < b }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func logError(context: String, error: Error) {
        if let httpError = error as? PlexHTTPError {
            print("\(context) error ratingKey=\(artistRatingKey) httpStatus=\(httpError.statusCode) message=\(httpError)")
        } else {
            print("\(context) error ratingKey=\(artistRatingKey) message=\(error)")
        }
    }

    nonisolated private static func logErrorStatic(context: String, ratingKey: String, error: Error) {
        if let httpError = error as? PlexHTTPError {
            print("\(context) error ratingKey=\(ratingKey) httpStatus=\(httpError.statusCode) message=\(httpError)")
        } else {
            print("\(context) error ratingKey=\(ratingKey) message=\(error)")
        }
    }

    private func enrichAlbumsWithDurations(
        albums: [PlexAlbum],
        tracks: [PlexTrack]
    ) -> [PlexAlbum] {
        let totals = tracks.reduce(into: [String: Int]()) { result, track in
            guard let albumKey = track.parentRatingKey, let duration = track.duration else { return }
            result[albumKey, default: 0] += duration
        }
        guard !totals.isEmpty else { return albums }
        return albums.map { album in
            guard album.duration == nil,
                  let total = totals[album.ratingKey] else {
                return album
            }
            return PlexAlbum(
                ratingKey: album.ratingKey,
                title: album.title,
                thumb: album.thumb,
                art: album.art,
                year: album.year,
                duration: total,
                originallyAvailableAt: album.originallyAvailableAt,
                artist: album.artist,
                titleSort: album.titleSort,
                originalTitle: album.originalTitle,
                editionTitle: album.editionTitle,
                guid: album.guid,
                librarySectionID: album.librarySectionID,
                parentRatingKey: album.parentRatingKey,
                studio: album.studio,
                summary: album.summary,
                genres: album.genres,
                styles: album.styles,
                moods: album.moods,
                rating: album.rating,
                userRating: album.userRating,
                key: album.key
            )
        }
    }

    private func loadAppearsOnAlbums(
        tracks: [PlexTrack],
        existingAlbums: [PlexAlbum],
        service: PlexLibraryServicing
    ) async -> [PlexAlbum] {
        guard !tracks.isEmpty else { return [] }
        let existingKeys = Set(existingAlbums.map(\.ratingKey))
        let appearsOnKeys = Set(tracks.compactMap(\.parentRatingKey)).subtracting(existingKeys)
        guard !appearsOnKeys.isEmpty else { return [] }

        let fetched = await fetchAlbumDetails(keys: Array(appearsOnKeys), service: service)
        let enriched = await enrichMissingDurationsFromTracks(albums: fetched, service: service)
        return sortAlbums(enriched)
    }

    private func mergeAlbums(primary: [PlexAlbum], appearsOn: [PlexAlbum]) -> [PlexAlbum] {
        guard !appearsOn.isEmpty else { return primary }
        var seen = Set(primary.map(\.ratingKey))
        let merged = primary + appearsOn.filter { seen.insert($0.ratingKey).inserted }
        return sortAlbums(merged)
    }

    private func fetchAlbumDetails(
        keys: [String],
        service: PlexLibraryServicing
    ) async -> [PlexAlbum] {
        let ratingKey = artistRatingKey
        return await withTaskGroup(of: PlexAlbum?.self) { group in
            for key in keys {
                group.addTask {
                    do {
                        return try await service.fetchAlbumDetail(albumRatingKey: key)
                    } catch {
                        Self.logErrorStatic(context: "ArtistDetail.fetchAlbumDetail", ratingKey: ratingKey, error: error)
                        return nil
                    }
                }
            }
            var results: [PlexAlbum] = []
            results.reserveCapacity(keys.count)
            for await album in group {
                if let album {
                    results.append(album)
                }
            }
            return results
        }
    }

    private func enrichMissingDurationsFromTracks(
        albums: [PlexAlbum],
        service: PlexLibraryServicing
    ) async -> [PlexAlbum] {
        let missing = albums.filter { $0.duration == nil }
        guard !missing.isEmpty else { return albums }

        let ratingKey = artistRatingKey
        var durationsByKey: [String: Int] = [:]
        await withTaskGroup(of: (String, Int?).self) { group in
            for album in missing {
                group.addTask {
                    do {
                        let tracks = try await service.fetchTracks(albumRatingKey: album.ratingKey)
                        let total = tracks.compactMap(\.duration).reduce(0, +)
                        return (album.ratingKey, total > 0 ? total : nil)
                    } catch {
                        Self.logErrorStatic(
                            context: "ArtistDetail.fetchAlbumTracks",
                            ratingKey: ratingKey,
                            error: error
                        )
                        return (album.ratingKey, nil)
                    }
                }
            }
            for await result in group {
                if let duration = result.1 {
                    durationsByKey[result.0] = duration
                }
            }
        }

        guard !durationsByKey.isEmpty else { return albums }
        return albums.map { album in
            guard album.duration == nil,
                  let duration = durationsByKey[album.ratingKey] else {
                return album
            }
            return PlexAlbum(
                ratingKey: album.ratingKey,
                title: album.title,
                thumb: album.thumb,
                art: album.art,
                year: album.year,
                duration: duration,
                originallyAvailableAt: album.originallyAvailableAt,
                artist: album.artist,
                titleSort: album.titleSort,
                originalTitle: album.originalTitle,
                editionTitle: album.editionTitle,
                guid: album.guid,
                librarySectionID: album.librarySectionID,
                parentRatingKey: album.parentRatingKey,
                studio: album.studio,
                summary: album.summary,
                genres: album.genres,
                styles: album.styles,
                moods: album.moods,
                rating: album.rating,
                userRating: album.userRating,
                key: album.key
            )
        }
    }

    private func makeNowPlayingContext(
        tracks: [PlexTrack],
        serverURL: URL,
        token: String
    ) -> NowPlayingContext? {
        let albumsByRatingKey = Dictionary(uniqueKeysWithValues: albums.map { ($0.ratingKey, $0) })
        guard let firstTrack = tracks.first else { return nil }
        let currentAlbum = firstTrack.parentRatingKey.flatMap { albumsByRatingKey[$0] } ?? albums.first
        guard let album = currentAlbum else { return nil }
        let builder = ArtworkRequestBuilder(baseURL: serverURL, token: token)
        let artworkRequests = albumsByRatingKey.reduce(into: [String: ArtworkRequest]()) { result, entry in
            if let request = builder.albumRequest(for: entry.value, size: .detail) {
                result[entry.key] = request
            }
        }
        let artworkRequest = artworkRequests[album.ratingKey]
        return NowPlayingContext(
            album: album,
            albumRatingKeys: [album.ratingKey],
            tracks: tracks,
            artworkRequest: artworkRequest,
            albumsByRatingKey: albumsByRatingKey,
            artworkRequestsByAlbumKey: artworkRequests
        )
    }
}
