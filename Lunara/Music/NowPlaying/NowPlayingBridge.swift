import Foundation
import MediaPlayer
import UIKit

/// Bridges playback state to the iOS lock screen and Control Center via
/// MPNowPlayingInfoCenter and MPRemoteCommandCenter.
@MainActor
final class NowPlayingBridge {

    private let engine: PlaybackEngineProtocol
    private let queue: QueueManagerProtocol
    private let resolver: NowPlayingResolver

    /// Track ID for which we last published metadata, to avoid redundant lookups.
    private var lastPublishedTrackID: String?
    /// Whether the last publish included artwork successfully.
    private var lastPublishHadArtwork = false
    private var observationTask: Task<Void, Never>?
    private var artworkRetryTask: Task<Void, Never>?
    /// The in-flight per-track publish (metadata + artwork). Cancelled and replaced
    /// when the current track changes, so a slow artwork fetch never blocks the next
    /// track's publish (Lunara-wtj).
    private var publishTask: Task<Void, Never>?

    #if DEBUG
    /// Test hook: the track ID the bridge has most recently published metadata for.
    var lastPublishedTrackIDForTesting: String? { lastPublishedTrackID }
    /// Test hook: whether the most recent publish applied artwork successfully.
    var lastPublishHadArtworkForTesting: Bool { lastPublishHadArtwork }
    #endif

    init(
        engine: PlaybackEngineProtocol,
        queue: QueueManagerProtocol,
        resolver: NowPlayingResolver
    ) {
        self.engine = engine
        self.queue = queue
        self.resolver = resolver
    }

    deinit {
        observationTask?.cancel()
        artworkRetryTask?.cancel()
        publishTask?.cancel()
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
                // Identity comes from the QUEUE, which advances immediately on a
                // skip/auto-advance — unlike engine.currentTrackID, which the engine
                // only sets after resolving + loading the track (Lunara-wtj).
                let trackID = self.queue.currentItem?.trackID
                let state = self.engine.playbackState
                let elapsed = self.engine.elapsed
                let duration = self.engine.duration

                self.handleStateChange(
                    trackID: trackID,
                    state: state,
                    elapsed: elapsed,
                    duration: duration
                )

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.queue.currentItem
                        _ = self.engine.playbackState
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// Synchronous: on a track change it spawns a cancellable `publishTask` and
    /// returns immediately, so the observation loop re-arms without waiting on the
    /// (possibly slow) artwork fetch. A non-track change just updates position.
    private func handleStateChange(
        trackID: String?,
        state: PlaybackState,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) {
        guard let trackID else {
            publishTask?.cancel()
            artworkRetryTask?.cancel()
            clearNowPlayingInfo()
            return
        }

        guard trackID != lastPublishedTrackID else {
            updatePlaybackPosition(state: state, elapsed: elapsed, duration: duration)
            return
        }

        // Record the new track BEFORE spawning, so a rapid follow-up skip's publish
        // guard (trackID == lastPublishedTrackID) rejects this now-superseded one.
        lastPublishedTrackID = trackID
        lastPublishHadArtwork = false
        artworkRetryTask?.cancel()
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            await self?.publishMetadata(trackID: trackID, state: state)
        }
    }

    // MARK: - Now Playing Info

    /// Publishes the new track's text immediately, then resolves artwork. Runs
    /// inside the cancellable `publishTask`; the post-await guards drop a publish
    /// that a newer track change has already superseded (cancellation is cooperative).
    private func publishMetadata(trackID: String, state: PlaybackState) async {
        let track = await resolver.track(id: trackID)
        guard !Task.isCancelled, trackID == lastPublishedTrackID, let track else { return }

        let album = await resolver.album(id: track.albumID)
        guard !Task.isCancelled, trackID == lastPublishedTrackID else { return }

        // Fresh track: start the scrubber at 0 against the track's own duration. The
        // engine may not have started this track yet, so its elapsed/duration still
        // describe the outgoing track; updatePlaybackPosition reconciles once it does.
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
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
        // The resolver fetches the full-size art and decodes it (downsampled, off the
        // main actor), sharing one decode with the now-playing screen. A failed decode
        // returns a nil image and is NOT memoized, so the retry below re-fetches.
        let image = await resolver.fullArtwork(for: album).image
        if let image {
            applyArtwork(image, forTrackID: trackID)
            lastPublishHadArtwork = true
        } else {
            scheduleArtworkRetry(album: album, forTrackID: trackID)
        }
    }

    private func applyArtwork(_ image: UIImage, forTrackID trackID: String) {
        guard trackID == lastPublishedTrackID,
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
            guard let self, !Task.isCancelled, self.lastPublishedTrackID == trackID else { return }
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
        lastPublishHadArtwork = false
        artworkRetryTask?.cancel()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
