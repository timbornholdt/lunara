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
        guard !tracks.isEmpty else {
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
            let fallback = fallbackURLBuilder.makeFallbackURL(for: track)
            return PlaybackQueueItem(track: track, primaryURL: source.url, fallbackURL: fallback)
        }
        guard !items.isEmpty else {
            onError?(PlaybackError(message: "Playback unavailable for this track."))
            return
        }
        let resolvedStart = resolveStartIndex(requestedStart: start, originalTracks: tracks, playableItems: items)
        do {
            try audioSession.configureForPlayback()
        } catch {
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
        publishState()
    }

    func refreshQueue(tracks: [PlexTrack], currentIndex: Int) {
        guard !tracks.isEmpty,
              !queueItems.isEmpty,
              currentIndex == self.currentIndex else {
            play(tracks: tracks, startIndex: currentIndex)
            return
        }
        guard currentIndex >= 0, currentIndex < tracks.count else {
            play(tracks: tracks, startIndex: currentIndex)
            return
        }

        let updatedItems = tracks.compactMap { track -> PlaybackQueueItem? in
            guard let source = sourceResolver.resolveSource(for: track) else { return nil }
            let fallback = fallbackURLBuilder.makeFallbackURL(for: track)
            return PlaybackQueueItem(track: track, primaryURL: source.url, fallbackURL: fallback)
        }
        guard currentIndex < updatedItems.count else {
            play(tracks: tracks, startIndex: currentIndex)
            return
        }

        let currentTrackKey = queueItems[self.currentIndex].track.ratingKey
        guard updatedItems[currentIndex].track.ratingKey == currentTrackKey else {
            play(tracks: tracks, startIndex: currentIndex)
            return
        }

        queueItems = updatedItems
        let upcomingURLs = (currentIndex + 1) < updatedItems.count
            ? Array(updatedItems[(currentIndex + 1)...]).map(\.primaryURL)
            : []
        player.replaceUpcoming(urls: upcomingURLs)
        publishState()
    }

    func stop() {
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
            player.pause()
        } else {
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
        currentIndex = newIndex
        currentElapsed = 0
        publishState()
    }

    private func handleItemFailure(index: Int) {
        let mappedIndex = queueBaseIndex + index
        guard mappedIndex >= 0, mappedIndex < queueItems.count else { return }
        if queueItems[mappedIndex].didUseFallback {
            onError?(PlaybackError(message: "Playback failed."))
            return
        }
        guard queueItems[mappedIndex].fallbackURL != nil else {
            onError?(PlaybackError(message: "Playback failed."))
            return
        }

        // Rebuild the remainder of the queue with remote fallback URLs to avoid AVQueue stalling
        // when a local asset cannot be opened.
        var fallbackURLs: [URL] = []
        fallbackURLs.reserveCapacity(queueItems.count - mappedIndex)
        for queueIndex in mappedIndex..<queueItems.count {
            let fallbackURL = queueItems[queueIndex].fallbackURL ?? queueItems[queueIndex].primaryURL
            if queueItems[queueIndex].fallbackURL != nil {
                queueItems[queueIndex].didUseFallback = true
            }
            fallbackURLs.append(fallbackURL)
        }

        queueBaseIndex = mappedIndex
        currentIndex = mappedIndex
        currentElapsed = 0
        player.setQueue(urls: fallbackURLs)
        player.play()
        isPlaying = true
        publishState()
    }

    private func handleTimeUpdate(_ time: TimeInterval) {
        currentElapsed = time
        publishState()
    }

    private func handlePlaybackStateChange(isPlaying: Bool) {
        self.isPlaying = isPlaying
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
            duration: durationSeconds,
            queueIndex: currentIndex
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
}

private struct PlaybackQueueItem {
    let track: PlexTrack
    let primaryURL: URL
    let fallbackURL: URL?
    var didUseFallback = false
}
