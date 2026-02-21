import Foundation
import MediaPlayer
import os
import UIKit

/// Bridges playback state to the iOS lock screen and Control Center via
/// MPNowPlayingInfoCenter and MPRemoteCommandCenter.
@MainActor
final class NowPlayingBridge {

    private let engine: PlaybackEngineProtocol
    private let queue: QueueManagerProtocol
    private let library: LibraryRepoProtocol
    private let artwork: ArtworkPipelineProtocol
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "NowPlayingBridge")

    /// Track ID for which we last published metadata, to avoid redundant lookups.
    private var lastPublishedTrackID: String?
    /// Whether the last publish included artwork successfully.
    private var lastPublishHadArtwork = false
    private var observationTask: Task<Void, Never>?
    private var artworkRetryTask: Task<Void, Never>?

    init(
        engine: PlaybackEngineProtocol,
        queue: QueueManagerProtocol,
        library: LibraryRepoProtocol,
        artwork: ArtworkPipelineProtocol
    ) {
        self.engine = engine
        self.queue = queue
        self.library = library
        self.artwork = artwork
    }

    deinit {
        observationTask?.cancel()
        artworkRetryTask?.cancel()
    }

    // MARK: - Public

    func configure() {
        registerRemoteCommands()
        startObserving()
    }

    // MARK: - Remote Commands

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.queue.play()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.queue.pause()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.queue.skipToNext()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.queue.skipBack()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.engine.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    // MARK: - Observation

    private func startObserving() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let trackID = self.engine.currentTrackID
                let state = self.engine.playbackState
                let elapsed = self.engine.elapsed
                let duration = self.engine.duration
                let queueIndex = self.queue.currentIndex

                await self.handleStateChange(
                    trackID: trackID,
                    state: state,
                    elapsed: elapsed,
                    duration: duration,
                    queueIndex: queueIndex
                )

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.engine.currentTrackID
                        _ = self.engine.playbackState
                        _ = self.engine.elapsed
                        _ = self.engine.duration
                        _ = self.queue.currentIndex
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// Tracks the queue index from the last publish so we detect skip-back-to-same-track.
    private var lastPublishedQueueIndex: Int?

    private func handleStateChange(
        trackID: String?,
        state: PlaybackState,
        elapsed: TimeInterval,
        duration: TimeInterval,
        queueIndex: Int?
    ) async {
        guard let trackID else {
            clearNowPlayingInfo()
            return
        }

        let isNewTrack = trackID != lastPublishedTrackID
        let queueIndexChanged = queueIndex != lastPublishedQueueIndex

        if isNewTrack || queueIndexChanged {
            lastPublishedTrackID = trackID
            lastPublishedQueueIndex = queueIndex
            lastPublishHadArtwork = false
            artworkRetryTask?.cancel()
            await publishMetadata(trackID: trackID, state: state, elapsed: elapsed, duration: duration)
        } else {
            updatePlaybackPosition(state: state, elapsed: elapsed, duration: duration)
        }
    }

    // MARK: - Now Playing Info

    private func publishMetadata(
        trackID: String,
        state: PlaybackState,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) async {
        let track: Track?
        do {
            track = try await library.track(id: trackID)
        } catch {
            logger.error("Failed to look up track \(trackID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            track = nil
        }

        guard let track else {
            updatePlaybackPosition(state: state, elapsed: elapsed, duration: duration)
            return
        }

        let album: Album?
        do {
            album = try await library.album(id: track.albumID)
        } catch {
            logger.error("Failed to look up album \(track.albumID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            album = nil
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]

        if let album {
            info[MPMediaItemPropertyAlbumTitle] = album.title
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Fetch artwork — may not be cached yet
        if let album {
            await loadAndApplyArtwork(album: album, forTrackID: trackID)
        }
    }

    private func loadAndApplyArtwork(album: Album, forTrackID trackID: String) async {
        let artworkURL: URL?
        do {
            artworkURL = try await artwork.fetchFullSize(
                for: album.plexID,
                ownerKind: .album,
                sourceURL: album.thumbURL.flatMap { URL(string: $0) }
            )
        } catch {
            logger.error("Failed to fetch artwork for album \(album.plexID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            artworkURL = nil
        }

        if let artworkURL, let imageData = try? Data(contentsOf: artworkURL), let image = UIImage(data: imageData) {
            applyArtwork(image, forTrackID: trackID)
            lastPublishHadArtwork = true
        } else {
            scheduleArtworkRetry(album: album, forTrackID: trackID)
        }
    }

    private func applyArtwork(_ image: UIImage, forTrackID trackID: String) {
        guard engine.currentTrackID == trackID,
              var current = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        let artworkItem = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        current[MPMediaItemPropertyArtwork] = artworkItem
        MPNowPlayingInfoCenter.default().nowPlayingInfo = current
    }

    private func scheduleArtworkRetry(album: Album, forTrackID trackID: String, attempt: Int = 1) {
        guard attempt <= 3 else { return }
        artworkRetryTask?.cancel()
        artworkRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(attempt) * 2))
            guard let self, !Task.isCancelled, self.engine.currentTrackID == trackID else { return }
            await self.loadAndApplyArtwork(album: album, forTrackID: trackID)
            if !self.lastPublishHadArtwork {
                self.scheduleArtworkRetry(album: album, forTrackID: trackID, attempt: attempt + 1)
            }
        }
    }

    private func updatePlaybackPosition(state: PlaybackState, elapsed: TimeInterval, duration: TimeInterval) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        lastPublishedTrackID = nil
        lastPublishedQueueIndex = nil
        lastPublishHadArtwork = false
        artworkRetryTask?.cancel()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
