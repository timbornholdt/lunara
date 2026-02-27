import Foundation
import Observation
import os

@MainActor
protocol TagFilterActionRouting: AlbumDetailActionRouting, AnyObject {
    func playAlbums(_ albums: [Album]) async throws
    func shuffleAlbums(_ albums: [Album]) async throws
}

extension AppCoordinator: TagFilterActionRouting { }

@MainActor
@Observable
final class TagFilterViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    var selectedGenres: Set<String> = []
    var selectedStyles: Set<String> = []
    var selectedMoods: Set<String> = []

    var availableGenres: [String] = []
    var availableStyles: [String] = []
    var availableMoods: [String] = []

    var albums: [Album] = []
    var loadingState: LoadingState = .idle
    var errorBannerState = ErrorBannerState()
    var artworkByAlbumID: [String: URL] = [:]

    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: TagFilterActionRouting
    private let downloadManager: DownloadManagerProtocol?
    private let gardenClient: GardenAPIClientProtocol?
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "TagFilterViewModel")
    private var pendingArtworkAlbumIDs: Set<String> = []

    init(
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: TagFilterActionRouting,
        downloadManager: DownloadManagerProtocol? = nil,
        gardenClient: GardenAPIClientProtocol? = nil,
        initialGenres: Set<String> = [],
        initialStyles: Set<String> = [],
        initialMoods: Set<String> = []
    ) {
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
        self.gardenClient = gardenClient
        self.selectedGenres = initialGenres
        self.selectedStyles = initialStyles
        self.selectedMoods = initialMoods
    }

    var filterDescription: String {
        let parts = [
            descriptionPart("Genres", selectedGenres),
            descriptionPart("Styles", selectedStyles),
            descriptionPart("Moods", selectedMoods)
        ].compactMap { $0 }

        if parts.isEmpty {
            return "All Albums"
        }
        return parts.joined(separator: " + ")
    }

    var hasActiveFilters: Bool {
        !selectedGenres.isEmpty || !selectedStyles.isEmpty || !selectedMoods.isEmpty
    }

    func loadIfNeeded() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading
        await loadAvailableTags()
        if hasActiveFilters {
            await applyFilter()
        } else {
            loadingState = .loaded
        }
    }

    func toggleGenre(_ genre: String) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else {
            selectedGenres.insert(genre)
        }
        Task { await applyFilter() }
    }

    func toggleStyle(_ style: String) {
        if selectedStyles.contains(style) {
            selectedStyles.remove(style)
        } else {
            selectedStyles.insert(style)
        }
        Task { await applyFilter() }
    }

    func toggleMood(_ mood: String) {
        if selectedMoods.contains(mood) {
            selectedMoods.remove(mood)
        } else {
            selectedMoods.insert(mood)
        }
        Task { await applyFilter() }
    }

    func applyFilter() async {
        guard hasActiveFilters else {
            albums = []
            loadingState = .loaded
            return
        }

        loadingState = .loading
        do {
            let results = try await fetchFilteredAlbums()
            albums = results.shuffled()
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    func playAll() async {
        guard !albums.isEmpty else { return }
        await runAction {
            try await actions.playAlbums(albums)
        }
    }

    func shuffle() async {
        guard !albums.isEmpty else { return }
        await runAction {
            try await actions.shuffleAlbums(albums)
        }
    }

    func playAlbum(_ album: Album) async {
        await runAction {
            try await actions.playAlbum(album)
        }
    }

    func queueAlbumNext(_ album: Album) async {
        await runAction {
            try await actions.queueAlbumNext(album)
        }
    }

    func queueAlbumLater(_ album: Album) async {
        await runAction {
            try await actions.queueAlbumLater(album)
        }
    }

    func makeAlbumDetailViewModel(for album: Album) -> AlbumDetailViewModel {
        AlbumDetailViewModel(
            album: album,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions,
            downloadManager: downloadManager,
            gardenClient: gardenClient,
            review: album.review,
            genres: album.genres.isEmpty ? nil : album.genres,
            styles: album.styles,
            moods: album.moods
        )
    }

    func albumThumbnailURL(for albumID: String) -> URL? {
        artworkByAlbumID[albumID]
    }

    func loadAlbumThumbnailIfNeeded(for album: Album) {
        guard albumThumbnailURL(for: album.plexID) == nil else { return }
        guard pendingArtworkAlbumIDs.insert(album.plexID).inserted else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let sourceURL = try await library.authenticatedArtworkURL(for: album.thumbURL)
                if let resolvedURL = try await artworkPipeline.fetchThumbnail(
                    for: album.plexID,
                    ownerKind: .album,
                    sourceURL: sourceURL
                ) {
                    self.artworkByAlbumID[album.plexID] = resolvedURL
                }
            } catch {
                // Artwork is non-blocking
            }
            self.pendingArtworkAlbumIDs.remove(album.plexID)
        }
    }

    // MARK: - Private

    private func fetchFilteredAlbums() async throws -> [Album] {
        var tagQueries: [(LibraryTagKind, String)] = []
        for genre in selectedGenres { tagQueries.append((.genre, genre)) }
        for style in selectedStyles { tagQueries.append((.style, style)) }
        for mood in selectedMoods { tagQueries.append((.mood, mood)) }

        guard let first = tagQueries.first else { return [] }

        let firstAlbums = try await library.albumsByTag(kind: first.0, value: first.1)
        var resultIDs = Set(firstAlbums.map(\.plexID))
        var albumsByID: [String: Album] = [:]
        for album in firstAlbums {
            albumsByID[album.plexID] = album
        }

        for query in tagQueries.dropFirst() {
            let tagAlbums = try await library.albumsByTag(kind: query.0, value: query.1)
            resultIDs.formIntersection(Set(tagAlbums.map(\.plexID)))
            for album in tagAlbums where resultIDs.contains(album.plexID) {
                albumsByID[album.plexID] = album
            }
        }

        return resultIDs.compactMap { albumsByID[$0] }
    }

    private func loadAvailableTags() async {
        do {
            async let genres = library.availableTags(kind: .genre)
            async let styles = library.availableTags(kind: .style)
            async let moods = library.availableTags(kind: .mood)
            availableGenres = try await genres
            availableStyles = try await styles
            availableMoods = try await moods
        } catch {
            logger.error("Failed to load available tags: \(error.localizedDescription)")
        }
    }

    private func runAction(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorBannerState.show(message: userFacingMessage(for: error))
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let lunaraError = error as? LunaraError {
            return lunaraError.userMessage
        }
        return error.localizedDescription
    }

    private func descriptionPart(_ label: String, _ values: Set<String>) -> String? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count <= 2 {
            return sorted.joined(separator: ", ")
        }
        return "\(sorted[0]) +\(sorted.count - 1) more"
    }
}
