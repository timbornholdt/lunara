import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class NowPlayingScreenViewModel {
    // MARK: - Exposed State

    private(set) var trackTitle: String?
    private(set) var artistName: String?
    private(set) var albumTitle: String?
    private(set) var albumID: String?
    private(set) var artworkImage: UIImage?
    private(set) var palette: ArtworkPaletteTheme = .default
    var playbackState: PlaybackState { engine.playbackState }
    var elapsed: TimeInterval { engine.elapsed }
    var duration: TimeInterval { engine.duration }
    private(set) var upNextItems: [UpNextItem] = []
    private(set) var currentAlbum: Album?
    private(set) var currentArtist: Artist?

    struct UpNextItem: Identifiable {
        let id: String
        let trackTitle: String
        let artistName: String
        let artworkImage: UIImage?
    }

    // MARK: - Dependencies

    private let queueManager: QueueManagerProtocol
    private let engine: PlaybackEngineProtocol
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol

    // MARK: - Private State

    private var resolvedTrackID: String?
    private var metadataTask: Task<Void, Never>?
    private var upNextTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        queueManager: QueueManagerProtocol,
        engine: PlaybackEngineProtocol,
        library: LibraryRepoProtocol,
        artworkPipeline: ArtworkPipelineProtocol
    ) {
        self.queueManager = queueManager
        self.engine = engine
        self.library = library
        self.artworkPipeline = artworkPipeline

        observeQueue()
        handleCurrentItemChange()
        resolveUpNext()
    }

    // MARK: - Actions

    func togglePlayPause() {
        switch engine.playbackState {
        case .playing, .buffering:
            queueManager.pause()
        case .paused:
            queueManager.resume()
        case .idle, .error:
            queueManager.play()
        }
    }

    func skipForward() {
        queueManager.skipToNext()
    }

    func skipBack() {
        queueManager.skipBack()
    }

    func commitSeek(to time: TimeInterval) {
        engine.seek(to: time)
    }

    // MARK: - Observation

    private func observeQueue() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.queueManager.currentItem
            _ = self.queueManager.items
            _ = self.queueManager.currentIndex
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleCurrentItemChange()
                self?.resolveUpNext()
                self?.observeQueue()
            }
        }
    }


    // MARK: - Track Resolution

    private func handleCurrentItemChange() {
        let newTrackID = queueManager.currentItem?.trackID
        guard newTrackID != resolvedTrackID else { return }
        resolvedTrackID = newTrackID

        metadataTask?.cancel()

        guard let trackID = newTrackID else {
            trackTitle = nil
            artistName = nil
            albumTitle = nil
            albumID = nil
            artworkImage = nil
            palette = .default
            currentAlbum = nil
            currentArtist = nil
            return
        }

        metadataTask = Task { [weak self] in
            await self?.resolveMetadata(for: trackID)
        }
    }

    private func resolveMetadata(for trackID: String) async {
        let track: Track?
        do {
            track = try await library.track(id: trackID)
        } catch {
            resolvedTrackID = nil
            return
        }

        guard let track else { return }
        guard !Task.isCancelled else { return }

        trackTitle = track.title
        artistName = track.artistName
        albumID = track.albumID

        // Resolve album
        if let album = try? await library.album(id: track.albumID) {
            guard !Task.isCancelled else { return }
            albumTitle = album.title
            currentAlbum = album
        }

        // Resolve artist
        if let artists = try? await library.searchArtists(query: track.artistName) {
            guard !Task.isCancelled else { return }
            currentArtist = artists.first { $0.name == track.artistName }
        }

        // Fetch full-size artwork
        let sourceURL: URL?
        if let album = currentAlbum {
            sourceURL = try? await library.authenticatedArtworkURL(for: album.thumbURL)
        } else {
            sourceURL = nil
        }

        let fileURL = try? await artworkPipeline.fetchFullSize(
            for: track.albumID,
            ownerKind: .album,
            sourceURL: sourceURL
        )
        guard !Task.isCancelled else { return }

        // Load image once into memory to avoid AsyncImage re-fetching on every re-render
        if let fileURL, let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            artworkImage = img
            palette = ArtworkPaletteExtractor.extract(from: img)
        } else {
            artworkImage = nil
            palette = .default
        }
    }

    // MARK: - Up Next Resolution

    private func resolveUpNext() {
        upNextTask?.cancel()
        upNextTask = Task { [weak self] in
            await self?.resolveUpNextItems()
        }
    }

    private func resolveUpNextItems() async {
        guard let currentIndex = queueManager.currentIndex else {
            upNextItems = []
            return
        }

        let items = queueManager.items
        let startIndex = currentIndex + 1
        let endIndex = min(startIndex + 20, items.count)
        guard startIndex < endIndex else {
            upNextItems = []
            return
        }

        let slice = items[startIndex..<endIndex]
        var resolved: [UpNextItem] = []

        for item in slice {
            guard !Task.isCancelled else { return }
            let track = try? await library.track(id: item.trackID)
            let albumID = track?.albumID ?? item.trackID
            let sourceURL: URL?
            if let track, let album = try? await library.album(id: track.albumID) {
                sourceURL = try? await library.authenticatedArtworkURL(for: album.thumbURL)
            } else {
                sourceURL = nil
            }
            let thumbURL = try? await artworkPipeline.fetchThumbnail(
                for: albumID,
                ownerKind: .album,
                sourceURL: sourceURL
            )
            var thumbImage: UIImage?
            if let thumbURL, let data = try? Data(contentsOf: thumbURL) {
                thumbImage = UIImage(data: data)
            }
            resolved.append(UpNextItem(
                id: item.trackID,
                trackTitle: track?.title ?? "Unknown Track",
                artistName: track?.artistName ?? "Unknown Artist",
                artworkImage: thumbImage
            ))
        }

        guard !Task.isCancelled else { return }
        upNextItems = resolved
    }
}
