import Foundation
import os

@MainActor
@Observable
final class ScrobbleManager {

    var isEnabled: Bool {
        get { LastFMSettings.load().isEnabled }
        set {
            var settings = LastFMSettings.load()
            settings.isEnabled = newValue
            settings.save()
        }
    }

    private let engine: PlaybackEngineProtocol
    private let queue: QueueManagerProtocol
    private let library: LibraryRepoProtocol
    private let client: LastFMClientProtocol
    private let authManager: LastFMAuthManager
    private let scrobbleQueue: ScrobbleQueue
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "ScrobbleManager")

    // MARK: - Track State

    private var lastNowPlayingTrackID: String?
    private var trackStartedAt: Date?
    private var hasScrobbled = false
    private var accumulatedPlayTime: TimeInterval = 0
    private var lastPlaybackState: PlaybackState = .idle
    private var lastStateChangeTime: Date?

    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    init(
        engine: PlaybackEngineProtocol,
        queue: QueueManagerProtocol,
        library: LibraryRepoProtocol,
        client: LastFMClientProtocol,
        authManager: LastFMAuthManager,
        scrobbleQueue: ScrobbleQueue = ScrobbleQueue()
    ) {
        self.engine = engine
        self.queue = queue
        self.library = library
        self.client = client
        self.authManager = authManager
        self.scrobbleQueue = scrobbleQueue
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Public

    func configure() {
        startObserving()
        Task { await flushQueue() }
    }

    func flushQueue() async {
        guard authManager.isAuthenticated, let sessionKey = authManager.sessionKey else { return }

        while await scrobbleQueue.pendingCount > 0 {
            let batch = await scrobbleQueue.dequeue(limit: 50)
            guard !batch.isEmpty else { break }

            do {
                try await client.scrobble(entries: batch, sessionKey: sessionKey)
                await scrobbleQueue.removeFront(batch.count)
                logger.info("Flushed \(batch.count) queued scrobbles")
            } catch {
                logger.error("Failed to flush scrobble queue: \(error.localizedDescription, privacy: .public)")
                break
            }
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

                await self.handleStateChange(
                    trackID: trackID,
                    state: state,
                    elapsed: elapsed,
                    duration: duration
                )

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.engine.currentTrackID
                        _ = self.engine.playbackState
                        _ = self.engine.elapsed
                        _ = self.engine.duration
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func handleStateChange(
        trackID: String?,
        state: PlaybackState,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) async {
        guard LastFMSettings.load().isEnabled, authManager.isAuthenticated else { return }

        // Track play time accumulation
        updateAccumulatedPlayTime(newState: state)

        guard let trackID else {
            resetTrackState()
            return
        }

        if trackID != lastNowPlayingTrackID {
            // New track started
            resetTrackState()
            lastNowPlayingTrackID = trackID
            trackStartedAt = Date()
            lastPlaybackState = state
            lastStateChangeTime = Date()

            if state == .playing {
                await sendNowPlaying(trackID: trackID)
            }
            return
        }

        // Same track — check if we should send now playing (e.g. resumed after buffering)
        if state == .playing && lastPlaybackState != .playing && lastNowPlayingTrackID != nil {
            // Just started playing (was buffering/paused before)
            if trackStartedAt == nil {
                await sendNowPlaying(trackID: trackID)
            }
        }

        lastPlaybackState = state
        lastStateChangeTime = Date()

        // Check scrobble threshold
        if !hasScrobbled && state == .playing {
            await checkScrobbleThreshold(trackID: trackID, duration: duration)
        }
    }

    private func updateAccumulatedPlayTime(newState: PlaybackState) {
        if lastPlaybackState == .playing, let lastChange = lastStateChangeTime {
            accumulatedPlayTime += Date().timeIntervalSince(lastChange)
        }
    }

    private func checkScrobbleThreshold(trackID: String, duration: TimeInterval) async {
        guard duration > 30 else { return }

        let threshold = min(duration * 0.5, 240)
        guard accumulatedPlayTime >= threshold else { return }

        hasScrobbled = true
        await submitScrobble(trackID: trackID, duration: duration)
    }

    // MARK: - API Calls

    private func sendNowPlaying(trackID: String) async {
        guard let sessionKey = authManager.sessionKey else { return }

        do {
            guard let track = try await library.track(id: trackID) else { return }
            let album = try? await library.album(id: track.albumID)

            try await client.updateNowPlaying(
                artist: track.artistName,
                track: track.title,
                album: album?.title,
                duration: Int(track.duration),
                sessionKey: sessionKey
            )
            logger.info("Now playing: \(track.title, privacy: .public) by \(track.artistName, privacy: .public)")
        } catch {
            logger.error("Failed to update now playing: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func submitScrobble(trackID: String, duration: TimeInterval) async {
        guard let timestamp = trackStartedAt.map({ Int($0.timeIntervalSince1970) }) else { return }

        do {
            guard let track = try await library.track(id: trackID) else { return }
            let album = try? await library.album(id: track.albumID)

            let entry = ScrobbleEntry(
                artist: track.artistName,
                track: track.title,
                album: album?.title,
                timestamp: timestamp,
                duration: Int(track.duration)
            )

            guard let sessionKey = authManager.sessionKey else {
                await scrobbleQueue.enqueue(entry)
                return
            }

            do {
                try await client.scrobble(entries: [entry], sessionKey: sessionKey)
                logger.info("Scrobbled: \(track.title, privacy: .public) by \(track.artistName, privacy: .public)")
                await flushQueue()
            } catch {
                logger.error("Scrobble failed, queuing: \(error.localizedDescription, privacy: .public)")
                await scrobbleQueue.enqueue(entry)
            }
        } catch {
            logger.error("Failed to look up track for scrobble: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func resetTrackState() {
        lastNowPlayingTrackID = nil
        trackStartedAt = nil
        hasScrobbled = false
        accumulatedPlayTime = 0
        lastPlaybackState = .idle
        lastStateChangeTime = nil
    }
}
