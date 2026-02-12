import Foundation

final class PlaybackEngine: PlaybackEngineing {
    var onStateChange: ((NowPlayingState?) -> Void)?
    var onError: ((PlaybackError) -> Void)?

    private let player: PlaybackPlayer
    private let sourceResolver: PlaybackSourceResolving
    private let fallbackURLBuilder: PlaybackFallbackURLBuilding
    private let audioSession: AudioSessionManaging

    private var queueItems: [PlaybackQueueItem] = []
    private var queueBaseIndex = 0
    private var currentIndex = 0
    private var currentElapsed: TimeInterval = 0
    private var isPlaying = false

    init(
        player: PlaybackPlayer = AVQueuePlayerAdapter(),
        sourceResolver: PlaybackSourceResolving,
        fallbackURLBuilder: PlaybackFallbackURLBuilding,
        audioSession: AudioSessionManaging = AudioSessionManager()
    ) {
        self.player = player
        self.sourceResolver = sourceResolver
        self.fallbackURLBuilder = fallbackURLBuilder
        self.audioSession = audioSession
        bindPlayerCallbacks()
    }

    func play(tracks: [PlexTrack], startIndex: Int) {
        log("play requested trackCount=\(tracks.count) startIndex=\(startIndex)")
        guard !tracks.isEmpty else {
            log("play aborted reason=empty_tracks")
            onError?(PlaybackError(message: "Playback unavailable for this track."))
            return
        }
        let start: Int
        if startIndex < 0 || startIndex >= tracks.count {
            start = 0
        } else {
            start = startIndex
        }

        let items = tracks.compactMap { track -> PlaybackQueueItem? in
            guard let source = sourceResolver.resolveSource(for: track) else { return nil }
            let fallback = fallbackURLBuilder.makeTranscodeURL(trackRatingKey: track.ratingKey)
            log("queue item track=\(track.ratingKey) source=\(source.url.absoluteString) fallback=\(fallback?.absoluteString ?? "nil")")
            return PlaybackQueueItem(track: track, primaryURL: source.url, fallbackURL: fallback)
        }
        guard !items.isEmpty else {
            log("play aborted reason=no_playable_items")
            onError?(PlaybackError(message: "Playback unavailable for this track."))
            return
        }
        let resolvedStart = resolveStartIndex(requestedStart: start, originalTracks: tracks, playableItems: items)
        log("resolved start index=\(resolvedStart)")
        do {
            try audioSession.configureForPlayback()
        } catch {
            log("audio session configure failed error=\(error.localizedDescription)")
            onError?(PlaybackError(message: "Playback failed."))
            return
        }

        queueItems = items
        queueBaseIndex = resolvedStart
        currentIndex = resolvedStart
        currentElapsed = 0
        player.setQueue(urls: items[resolvedStart...].map { $0.primaryURL })
        player.play()
        isPlaying = true
        log("play started queueSize=\(items.count - resolvedStart)")
        publishState()
    }

    func stop() {
        log("stop requested")
        player.stop()
        queueItems.removeAll()
        queueBaseIndex = 0
        currentIndex = 0
        currentElapsed = 0
        isPlaying = false
        onStateChange?(nil)
    }

    func togglePlayPause() {
        guard !queueItems.isEmpty else { return }
        if isPlaying {
            log("toggle -> pause")
            player.pause()
        } else {
            log("toggle -> play")
            player.play()
        }
    }

    func skipToNext() {
        let nextIndex = currentIndex + 1
        guard nextIndex < queueItems.count else { return }
        jump(to: nextIndex)
    }

    func skipToPrevious() {
        let previousIndex = max(currentIndex - 1, 0)
        guard previousIndex < queueItems.count else { return }
        jump(to: previousIndex)
    }

    func seek(to seconds: TimeInterval) {
        guard !queueItems.isEmpty else { return }
        player.seek(to: seconds)
    }

    private func bindPlayerCallbacks() {
        player.onItemChanged = { [weak self] index in
            self?.handleItemChanged(index: index)
        }
        player.onItemFailed = { [weak self] index in
            self?.handleItemFailure(index: index)
        }
        player.onTimeUpdate = { [weak self] time in
            self?.handleTimeUpdate(time)
        }
        player.onPlaybackStateChanged = { [weak self] playing in
            self?.handlePlaybackStateChange(isPlaying: playing)
        }
    }

    private func handleItemChanged(index: Int) {
        let newIndex = queueBaseIndex + index
        guard newIndex >= 0, newIndex < queueItems.count else { return }
        log("item changed index=\(index) mappedIndex=\(newIndex)")
        currentIndex = newIndex
        currentElapsed = 0
        publishState()
    }

    private func handleItemFailure(index: Int) {
        let mappedIndex = queueBaseIndex + index
        guard mappedIndex >= 0, mappedIndex < queueItems.count else { return }
        log("item failed index=\(index) mappedIndex=\(mappedIndex) didUseFallback=\(queueItems[mappedIndex].didUseFallback)")
        if queueItems[mappedIndex].didUseFallback {
            log("playback failure after fallback track=\(queueItems[mappedIndex].track.ratingKey)")
            onError?(PlaybackError(message: "Playback failed."))
            return
        }
        guard let fallbackURL = queueItems[mappedIndex].fallbackURL else {
            log("no fallback url for track=\(queueItems[mappedIndex].track.ratingKey)")
            onError?(PlaybackError(message: "Playback failed."))
            return
        }
        queueItems[mappedIndex].didUseFallback = true
        log("replacing current item with fallback url=\(fallbackURL.absoluteString)")
        player.replaceCurrentItem(url: fallbackURL)
    }

    private func handleTimeUpdate(_ time: TimeInterval) {
        currentElapsed = time
        publishState()
    }

    private func handlePlaybackStateChange(isPlaying: Bool) {
        self.isPlaying = isPlaying
        log("playback state changed isPlaying=\(isPlaying)")
        publishState()
    }

    private func publishState() {
        guard !queueItems.isEmpty, currentIndex < queueItems.count else {
            onStateChange?(nil)
            return
        }
        let item = queueItems[currentIndex]
        let durationSeconds = item.track.duration.map { Double($0) / 1000.0 }
        let state = NowPlayingState(
            trackRatingKey: item.track.ratingKey,
            trackTitle: item.track.title,
            artistName: item.track.originalTitle ?? item.track.grandparentTitle,
            isPlaying: isPlaying,
            elapsedTime: currentElapsed,
            duration: durationSeconds
        )
        onStateChange?(state)
    }

    private func jump(to index: Int) {
        guard index >= 0, index < queueItems.count else { return }
        queueBaseIndex = index
        currentIndex = index
        currentElapsed = 0
        player.setQueue(urls: queueItems[index...].map { $0.primaryURL })
        player.play()
        isPlaying = true
        publishState()
    }

    private func resolveStartIndex(
        requestedStart: Int,
        originalTracks: [PlexTrack],
        playableItems: [PlaybackQueueItem]
    ) -> Int {
        guard requestedStart < originalTracks.count else {
            return 0
        }

        for index in requestedStart..<originalTracks.count {
            let key = originalTracks[index].ratingKey
            if let playableIndex = playableItems.firstIndex(where: { $0.track.ratingKey == key }) {
                return playableIndex
            }
        }

        return 0
    }

    private func log(_ message: String) {
        NSLog("[PlaybackDebug][Engine] %@", message)
    }
}

private struct PlaybackQueueItem {
    let track: PlexTrack
    let primaryURL: URL
    let fallbackURL: URL?
    var didUseFallback = false
}
