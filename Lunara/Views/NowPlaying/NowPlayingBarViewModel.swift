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
    var playbackState: PlaybackState { engine.playbackState }

    var isVisible: Bool {
        // Show the bar when something is actively playing, paused, or buffering.
        // Also stay visible during brief .idle moments between tracks (auto-advance)
        // to avoid the bar/sheet disappearing and re-animating.
        // A restored queue on launch leaves the engine in .idle with hasBegunPlayback
        // still false — we don't want the bar to appear before the user has explicitly
        // started playback.
        queueManager.currentItem != nil && (playbackState != .idle || hasBegunPlayback)
    }

    // MARK: - Dependencies

    private let queueManager: QueueManagerProtocol
    private let engine: PlaybackEngineProtocol
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol

    // MARK: - Private State

    private var resolvedTrackID: String?
    private var metadataTask: Task<Void, Never>?
    /// Tracks whether the user has started playback this session.
    /// Prevents the bar from appearing on launch with a restored-but-idle queue,
    /// while keeping it visible during brief idle gaps between tracks.
    private var hasBegunPlayback = false

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
        observePlaybackState()
        handleCurrentItemChange()
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

    private func observePlaybackState() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.engine.playbackState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.engine.playbackState == .playing || self.engine.playbackState == .buffering {
                    self.hasBegunPlayback = true
                }
                self.observePlaybackState()
            }
        }
    }

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
            hasBegunPlayback = false
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
            // Track lookup failed (e.g. database error). Reset so the next
            // track change can retry rather than staying stuck on stale state.
            resolvedTrackID = nil
            return
        }

        guard let track else { return }
        guard !Task.isCancelled else { return }

        trackTitle = track.title
        artistName = track.artistName

        // Resolve an authenticated artwork URL so the pipeline can fetch the
        // thumbnail from the server if it isn't already cached locally.
        let sourceURL: URL?
        if let album = try? await library.album(id: track.albumID) {
            sourceURL = try? await library.authenticatedArtworkURL(for: album.thumbURL)
        } else {
            sourceURL = nil
        }

        let fileURL = try? await artworkPipeline.fetchThumbnail(
            for: track.albumID,
            ownerKind: .album,
            sourceURL: sourceURL
        )
        guard !Task.isCancelled else { return }
        artworkFileURL = fileURL
    }
}
