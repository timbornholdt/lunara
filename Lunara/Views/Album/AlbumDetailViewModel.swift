import Foundation
import Observation
import os
import UIKit

@MainActor
protocol AlbumDetailActionRouting: AnyObject {
    func playAlbum(_ album: Album) async throws
    func queueAlbumNext(_ album: Album) async throws
    func queueAlbumLater(_ album: Album) async throws
    func playTrackNow(_ track: Track) async throws
    func queueTrackNext(_ track: Track) async throws
    func queueTrackLater(_ track: Track) async throws
}

extension AppCoordinator: AlbumDetailActionRouting { }

@MainActor
@Observable
final class AlbumDetailViewModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    let album: Album
    var review: String?
    var genres: [String]
    var styles: [String]
    var moods: [String]

    var tracks: [Track] = []
    var loadingState: LoadingState = .idle
    var errorBannerState = ErrorBannerState()
    var artworkURL: URL?
    var palette: ArtworkPaletteTheme = .default

    var albumDownloadState: AlbumDownloadState = .idle

    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol
    private let actions: AlbumDetailActionRouting
    private let downloadManager: DownloadManagerProtocol?
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "AlbumDetailViewModel")
    private var backgroundRefreshTask: Task<Void, Never>?

    init(
        album: Album,
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol,
        actions: AlbumDetailActionRouting,
        downloadManager: DownloadManagerProtocol? = nil,
        review: String? = nil,
        genres: [String]? = nil,
        styles: [String] = [],
        moods: [String] = []
    ) {
        self.album = album
        self.library = library
        self.artworkPipeline = artworkPipeline
        self.actions = actions
        self.downloadManager = downloadManager
        self.review = (review ?? album.review)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.genres = Self.normalizedTags(genres ?? (!album.genres.isEmpty ? album.genres : (album.genre.map { [$0] } ?? [])))
        self.styles = Self.normalizedTags(styles.isEmpty ? album.styles : styles)
        self.moods = Self.normalizedTags(moods.isEmpty ? album.moods : moods)
    }

    func loadIfNeeded() async {
        guard case .idle = loadingState else {
            return
        }

        loadingState = .loading
        await loadAlbumMetadata()
        await loadTracks()
        await loadArtwork()
        startBackgroundDetailRefresh()
    }

    func playAlbum() async {
        await runAction {
            try await actions.playAlbum(album)
        }
    }

    func queueAlbumNext() async {
        await runAction {
            try await actions.queueAlbumNext(album)
        }
    }

    func queueAlbumLater() async {
        await runAction {
            try await actions.queueAlbumLater(album)
        }
    }

    func playTrackNow(_ track: Track) async {
        await runAction {
            try await actions.playTrackNow(track)
        }
    }

    func queueTrackNext(_ track: Track) async {
        await runAction {
            try await actions.queueTrackNext(track)
        }
    }

    func queueTrackLater(_ track: Track) async {
        await runAction {
            try await actions.queueTrackLater(track)
        }
    }

    func downloadAlbum() async {
        guard let downloadManager else {
            logger.warning("downloadAlbum: no downloadManager — skipping")
            return
        }
        let albumID = self.album.plexID
        let trackList = self.tracks
        logger.info("downloadAlbum: starting for album '\(albumID, privacy: .public)' with \(trackList.count) tracks")
        if trackList.isEmpty {
            logger.warning("downloadAlbum: track list is empty — nothing to download")
            return
        }
        await downloadManager.downloadAlbum(self.album, tracks: trackList)
        self.albumDownloadState = downloadManager.downloadState(forAlbum: albumID)
        let stateDesc = String(describing: self.albumDownloadState)
        logger.info("downloadAlbum: finished with state \(stateDesc, privacy: .public)")
    }

    func removeDownload() async {
        guard let downloadManager else { return }
        try? await downloadManager.removeDownload(forAlbum: album.plexID)
        albumDownloadState = downloadManager.downloadState(forAlbum: album.plexID)
    }

    func refreshDownloadState() async {
        guard let downloadManager else {
            logger.info("refreshDownloadState: no downloadManager")
            return
        }
        albumDownloadState = await downloadManager.resolvedDownloadState(
            forAlbum: album.plexID,
            totalTrackCount: tracks.isEmpty ? album.trackCount : tracks.count
        )
    }

    private func loadTracks() async {
        do {
            tracks = try await library.tracks(forAlbum: album.plexID)
            loadingState = .loaded
        } catch {
            loadingState = .error(userFacingMessage(for: error))
        }
    }

    private func loadArtwork() async {
        do {
            let sourceURL = try await library.authenticatedArtworkURL(for: album.thumbURL)
            let url = try await artworkPipeline.fetchFullSize(
                for: album.plexID,
                ownerKind: .album,
                sourceURL: sourceURL
            )
            artworkURL = url
            if let url, let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                palette = ArtworkPaletteExtractor.extract(from: img)
            }
        } catch {
            // Artwork is non-blocking for detail presentation.
        }
    }

    private func loadAlbumMetadata() async {
        do {
            guard let cachedAlbum = try await library.album(id: album.plexID) else {
                return
            }
            applyAlbumMetadata(cachedAlbum)
        } catch {
            // Metadata enrichment is best-effort; leave existing values when fetch fails.
        }
    }

    private func startBackgroundDetailRefresh() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let outcome = try await library.refreshAlbumDetail(albumID: album.plexID)
                if let refreshedAlbum = outcome.album {
                    applyAlbumMetadata(refreshedAlbum)
                }
                tracks = outcome.tracks
                loadingState = .loaded
            } catch {
                // Keep currently rendered cache when background refresh fails.
            }
        }
    }

    private func applyAlbumMetadata(_ refreshedAlbum: Album) {
        if let refreshedReview = refreshedAlbum.review?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            review = refreshedReview
        }

        let refreshedGenres = Self.normalizedTags(refreshedAlbum.genres)
        if !refreshedGenres.isEmpty {
            genres = refreshedGenres
        } else if genres.isEmpty, let genre = refreshedAlbum.genre {
            genres = Self.normalizedTags([genre])
        }

        let refreshedStyles = Self.normalizedTags(refreshedAlbum.styles)
        if !refreshedStyles.isEmpty {
            styles = refreshedStyles
        }

        let refreshedMoods = Self.normalizedTags(refreshedAlbum.moods)
        if !refreshedMoods.isEmpty {
            moods = refreshedMoods
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

    func findArtist() async -> Artist? {
        let artists = try? await library.searchArtists(query: album.artistName)
        return artists?.first { $0.name == album.artistName }
    }

    func makeArtistDetailViewModel(for artist: Artist) -> ArtistDetailViewModel {
        ArtistDetailViewModel(
            artist: artist,
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions as! ArtistsListActionRouting,
            downloadManager: downloadManager
        )
    }

    func makeTagFilterViewModel(
        initialGenres: Set<String>,
        initialStyles: Set<String>,
        initialMoods: Set<String>
    ) -> TagFilterViewModel {
        TagFilterViewModel(
            library: library,
            artworkPipeline: artworkPipeline,
            actions: actions as! TagFilterActionRouting,
            downloadManager: downloadManager,
            initialGenres: initialGenres,
            initialStyles: initialStyles,
            initialMoods: initialMoods
        )
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        var deduped: [String] = []
        var seen = Set<String>()
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }
            deduped.append(trimmed)
        }
        return deduped
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
