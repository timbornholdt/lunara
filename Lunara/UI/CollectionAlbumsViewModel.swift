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
    private let diagnostics: DiagnosticsLogging
    private var albumGroups: [String: [PlexAlbum]] = [:]
    private var hasLoaded = false
    private var backgroundFillTask: Task<Void, Never>?

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
        cacheStore: LibraryCacheStoring = LibraryCacheStore(),
        diagnostics: DiagnosticsLogging = DiagnosticsLogger.shared
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
        self.diagnostics = diagnostics
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
        backgroundFillTask?.cancel()
        backgroundFillTask = nil
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

        do {
            let service = libraryServiceFactory(serverURL, token)

            if !shuffled {
                // Non-shuffle: fetch all tracks in parallel, play in order
                let allAlbumKeys = albums.flatMap { ratingKeys(for: $0) }
                let combinedTracks = try await fetchTracksForAlbums(allAlbumKeys, using: service)
                isPreparingPlayback = false
                guard combinedTracks.isEmpty == false else {
                    errorMessage = "No tracks found in this collection."
                    return
                }
                playbackController.play(
                    tracks: combinedTracks,
                    startIndex: 0,
                    context: makeNowPlayingContext(tracks: combinedTracks, serverURL: serverURL, token: token)
                )
                return
            }

            // Two-phase shuffle: start audio fast, fill queue in background
            let shuffleStart = Date()
            diagnostics.log(.shuffleStarted(albumCount: albums.count))
            let shuffledAlbums = albums.shuffled()
            let phase1Albums = Array(shuffledAlbums.prefix(5))
            let phase1Keys = phase1Albums.flatMap { ratingKeys(for: $0) }
            var seenTrackKeys = Set<String>()

            let phase1Tracks = try await fetchTracksForAlbums(phase1Keys, using: service)
            isPreparingPlayback = false
            guard phase1Tracks.isEmpty == false else {
                errorMessage = "No tracks found in this collection."
                return
            }
            let shuffledPhase1 = shuffleProvider(phase1Tracks)
            for track in shuffledPhase1 {
                seenTrackKeys.insert(track.ratingKey)
            }
            playbackController.play(
                tracks: shuffledPhase1,
                startIndex: 0,
                context: makeNowPlayingContext(tracks: shuffledPhase1, serverURL: serverURL, token: token)
            )
            let phase1DurationMs = Int(Date().timeIntervalSince(shuffleStart) * 1000)
            diagnostics.log(.shufflePhase1Complete(trackCount: shuffledPhase1.count, durationMs: phase1DurationMs))

            // Phase 2: Background fill
            let remainingAlbums = Array(shuffledAlbums.dropFirst(5))
            guard !remainingAlbums.isEmpty else { return }
            let remainingKeys = remainingAlbums.flatMap { ratingKeys(for: $0) }
            let capturedSeenKeys = seenTrackKeys
            let capturedShuffleProvider = shuffleProvider
            let capturedPlaybackController = playbackController

            let capturedDiagnostics = diagnostics
            let phase2Start = Date()
            backgroundFillTask = Task { [weak self] in
                var seenKeys = capturedSeenKeys
                var allPhase2Tracks: [PlexTrack] = []
                let batchSize = 10
                for batchStart in stride(from: 0, to: remainingKeys.count, by: batchSize) {
                    guard !Task.isCancelled else { return }
                    let batchEnd = min(batchStart + batchSize, remainingKeys.count)
                    let batchKeys = Array(remainingKeys[batchStart..<batchEnd])
                    do {
                        let batchTracks = try await self?.fetchTracksForAlbums(batchKeys, using: service)
                        guard let batchTracks, !Task.isCancelled else { return }
                        for track in batchTracks where seenKeys.insert(track.ratingKey).inserted {
                            allPhase2Tracks.append(track)
                        }
                    } catch {
                        continue
                    }
                }
                guard !allPhase2Tracks.isEmpty, !Task.isCancelled else { return }
                let shuffledAll = capturedShuffleProvider(allPhase2Tracks)
                await MainActor.run {
                    let context = self?.makeNowPlayingContext(
                        tracks: shuffledAll,
                        serverURL: serverURL,
                        token: token
                    )
                    capturedPlaybackController.enqueue(
                        mode: .playLater,
                        tracks: shuffledAll,
                        context: context
                    )
                }
                let phase2DurationMs = Int(Date().timeIntervalSince(phase2Start) * 1000)
                await MainActor.run {
                    capturedDiagnostics.log(.shufflePhase2Complete(trackCount: allPhase2Tracks.count, durationMs: phase2DurationMs))
                }
            }
        } catch {
            isPreparingPlayback = false
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

    private func fetchTracksForAlbums(
        _ albumRatingKeys: [String],
        using service: PlexLibraryServicing
    ) async throws -> [PlexTrack] {
        var tracksByKey: [String: [PlexTrack]] = [:]
        try await withThrowingTaskGroup(of: (String, [PlexTrack]).self) { group in
            for key in albumRatingKeys {
                group.addTask {
                    let tracks = try await service.fetchTracks(albumRatingKey: key)
                    return (key, tracks)
                }
            }
            for try await (key, tracks) in group {
                tracksByKey[key] = sortTracks(tracks)
            }
        }
        var combined: [PlexTrack] = []
        var seenTrackKeys = Set<String>()
        for key in albumRatingKeys {
            guard let tracks = tracksByKey[key] else { continue }
            for track in tracks where seenTrackKeys.insert(track.ratingKey).inserted {
                combined.append(track)
            }
        }
        return combined
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
