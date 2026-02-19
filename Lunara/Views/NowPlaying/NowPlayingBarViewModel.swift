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
        // Only show the bar when something is actively playing or paused.
        // A restored queue on launch leaves the engine in .idle — we don't
        // want the bar to appear before the user has explicitly started playback.
        queueManager.currentItem != nil && playbackState != .idle
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

        // Eagerly resolve state in case the VM is initialized while the queue
        // already has a current item (e.g. relaunched mid-session, or parent
        // view re-rendered). The observation only fires on *change*, so without
        // this we'd show a blank bar until the next track transition.
        playbackState = engine.playbackState
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

        // sourceURL is nil: the pipeline serves from disk cache only.
        // The grid and album detail views warm the thumbnail cache, so this
        // will succeed for any album the user has browsed. If not cached yet,
        // artworkFileURL stays nil and the placeholder is shown — that's fine.
        let fileURL = try? await artworkPipeline.fetchThumbnail(
            for: track.albumID,
            ownerKind: .album,
            sourceURL: nil
        )
        guard !Task.isCancelled else { return }
        artworkFileURL = fileURL
    }
}
