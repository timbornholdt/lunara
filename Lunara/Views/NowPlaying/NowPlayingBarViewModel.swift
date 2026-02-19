import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class NowPlayingBarViewModel {
    // MARK: - Exposed State

    private(set) var trackTitle: String?
    private(set) var artistName: String?
    private(set) var artworkFileURL: URL?
    private(set) var playbackState: PlaybackState = .idle

    var isVisible: Bool {
        queueManager.currentItem != nil
    }

    // MARK: - Dependencies

    private let queueManager: QueueManagerProtocol
    private let engine: PlaybackEngineProtocol
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol

    // MARK: - Private State

    private var resolvedTrackID: String?
    private var metadataTask: Task<Void, Never>?

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
        observeEngine()
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

    // MARK: - Observation

    private func observeQueue() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.queueManager.currentItem
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleCurrentItemChange()
                self?.observeQueue()
            }
        }
    }

    private func observeEngine() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.engine.playbackState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.playbackState = self?.engine.playbackState ?? .idle
                self?.observeEngine()
            }
        }
    }

    // MARK: - Track Resolution

    private func handleCurrentItemChange() {
        let newTrackID = queueManager.currentItem?.trackID

        // Avoid redundant resolution if the track hasn't changed.
        guard newTrackID != resolvedTrackID else { return }
        resolvedTrackID = newTrackID

        metadataTask?.cancel()

        guard let trackID = newTrackID else {
            trackTitle = nil
            artistName = nil
            artworkFileURL = nil
            return
        }

        metadataTask = Task { [weak self] in
            await self?.resolveMetadata(for: trackID)
        }
    }

    private func resolveMetadata(for trackID: String) async {
        guard let track = try? await library.track(id: trackID) else { return }
        guard !Task.isCancelled else { return }

        trackTitle = track.title
        artistName = track.artistName

        let sourceURL: URL? = nil // Artwork source URL not needed; pipeline reads from its own cache.
        let fileURL = try? await artworkPipeline.fetchThumbnail(
            for: track.albumID,
            ownerKind: .album,
            sourceURL: sourceURL
        )
        guard !Task.isCancelled else { return }
        artworkFileURL = fileURL
    }
}
