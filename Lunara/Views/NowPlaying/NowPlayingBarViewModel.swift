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
        // Show the bar while a queue exists and playback has begun this session.
        // queueManager.hasPlaybackBegun latches SYNCHRONOUSLY in playNow/play —
        // the old engine-state latch raced the async observer, so mid-start
        // idle bounces flapped the iOS 26 accessory off/on, tearing down the
        // Now Playing sheet host in a dismiss/re-present loop (Lunara-m73).
        // A restored queue on launch stays hidden until the user explicitly plays.
        queueManager.currentItem != nil
            && (playbackState != .idle || hasBegunPlayback || queueManager.hasPlaybackBegun)
    }

    // MARK: - Dependencies

    private let queueManager: QueueManagerProtocol
    private let engine: PlaybackEngineProtocol
    private let resolver: NowPlayingResolver

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
        resolver: NowPlayingResolver
    ) {
        self.queueManager = queueManager
        self.engine = engine
        self.resolver = resolver

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
        guard let track = await resolver.track(id: trackID) else {
            // Resolution failed (e.g. database error). Reset so the next track
            // change can retry rather than staying stuck on stale state.
            resolvedTrackID = nil
            return
        }
        guard !Task.isCancelled else { return }

        trackTitle = track.title
        artistName = track.artistName

        // The resolver fetches the thumbnail (server fetch if not cached) keyed on
        // the album, sharing the lookup with the now-playing screen and bridge.
        let fileURL: URL?
        if let album = await resolver.album(id: track.albumID) {
            fileURL = await resolver.thumbnailURL(for: album)
        } else {
            fileURL = nil
        }
        guard !Task.isCancelled else { return }
        artworkFileURL = fileURL
    }
}
