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
    private(set) var waveformLevels: [Float]?

    struct UpNextItem: Identifiable {
        let id: String
        let queueIndex: Int
        let trackTitle: String
        let artistName: String
        let artworkImage: UIImage?
    }

    // Pre-resolved snapshot of all display data for a track,
    // used to apply all UI updates atomically in a single frame.
    private struct TrackSnapshot {
        let trackTitle: String
        let artistName: String
        let albumTitle: String?
        let albumID: String
        let artworkImage: UIImage?
        let palette: ArtworkPaletteTheme
        let album: Album?
        let artist: Artist?
        let waveformLevels: [Float]?
    }

    // MARK: - Dependencies

    private let queueManager: QueueManagerProtocol
    private let engine: PlaybackEngineProtocol
    /// Still used directly for artist + loudness, which the shared resolver does not own.
    private let library: LibraryRepoProtocol
    private let resolver: NowPlayingResolver

    // MARK: - Private State

    private var resolvedTrackID: String?
    private var metadataTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchingTrackID: String?
    private var upNextTask: Task<Void, Never>?
    private var snapshotCache: [String: TrackSnapshot] = [:]

    /// Rendered size of an up-next row thumbnail; artwork is downsampled to this.
    private static let upNextThumbnailPointSize = CGSize(width: 40, height: 40)
    /// Number of up-next rows resolved + published eagerly before the long tail, so the
    /// visible top of Up Next paints without waiting on a full window rebuild.
    private static let upNextEagerCount = 5
    /// Fixed display scale used when downsampling (matches the target device; keeps decoding deterministic).
    private let displayScale: CGFloat = 3

    #if DEBUG
    /// Test hook: number of retained track snapshots (bounded to current + next).
    var snapshotCacheCountForTesting: Int { snapshotCache.count }
    #endif

    // MARK: - Initialization

    init(
        queueManager: QueueManagerProtocol,
        engine: PlaybackEngineProtocol,
        library: LibraryRepoProtocol,
        resolver: NowPlayingResolver
    ) {
        self.queueManager = queueManager
        self.engine = engine
        self.library = library
        self.resolver = resolver

        observeQueue()
        handleCurrentItemChange()
        resolveUpNextIfNeeded()
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

    func skipToQueueItem(_ item: UpNextItem) {
        queueManager.skipTo(index: item.queueIndex)
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
                self?.resolveUpNextIfNeeded()
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
            withAnimation(.easeInOut(duration: 0.3)) {
                trackTitle = nil
                artistName = nil
                albumTitle = nil
                albumID = nil
                artworkImage = nil
                palette = .default
                currentAlbum = nil
                currentArtist = nil
                waveformLevels = nil
            }
            return
        }

        // If we have a pre-fetched snapshot, apply it immediately.
        if let cached = snapshotCache[trackID] {
            applySnapshot(cached)
            evictStaleSnapshots()
            prefetchNextTrack()
            return
        }

        metadataTask = Task { [weak self] in
            await self?.resolveAndApply(trackID: trackID)
        }
    }

    private func resolveAndApply(trackID: String) async {
        // Phase 1 — apply the new track's TEXT immediately and clear the previous
        // track's artwork/palette/waveform, so the old album art is never shown
        // next to the new track's metadata while the (possibly networked) artwork
        // fetch is still in flight.
        guard let track = await resolver.track(id: trackID) else { return }
        guard !Task.isCancelled else { return }
        let album = await resolver.album(id: track.albumID)
        guard !Task.isCancelled else { return }
        applyTextClearingVisuals(track: track, album: album)

        // Start the slower, independent legs in parallel so none gates the others.
        async let artistTask = resolveArtist(forName: track.artistName)
        async let levelsTask = resolveLoudness(plexID: track.plexID)

        // Phase 2a — artwork + palette: apply the moment the image is decoded, so it
        // is never held behind the artist/loudness fetches.
        let (image, palette) = await resolveArtwork(track: track, album: album)
        guard !Task.isCancelled else { return }
        applyArtwork(image: image, palette: palette)

        // Phase 2b — artist + waveform, applied when they arrive.
        let artist = await artistTask
        let levels = await levelsTask
        guard !Task.isCancelled else { return }
        applyArtistAndWaveform(artist: artist, levels: levels)

        snapshotCache[trackID] = TrackSnapshot(
            trackTitle: track.title,
            artistName: track.artistName,
            albumTitle: album?.title,
            albumID: track.albumID,
            artworkImage: image,
            palette: palette,
            album: album,
            artist: artist,
            waveformLevels: levels
        )
        evictStaleSnapshots()
        prefetchNextTrack()
    }

    /// Applies the new track's text metadata at once and clears every visual that
    /// belonged to the previous track (artwork, palette, artist, waveform), so a
    /// stale album cover can't linger while the new artwork resolves.
    private func applyTextClearingVisuals(track: Track, album: Album?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            trackTitle = track.title
            artistName = track.artistName
            albumTitle = album?.title
            albumID = track.albumID
            currentAlbum = album
            artworkImage = nil
            palette = .default
            currentArtist = nil
            waveformLevels = nil
        }
    }

    private func applySnapshot(_ snapshot: TrackSnapshot) {
        withAnimation(.easeInOut(duration: 0.3)) {
            trackTitle = snapshot.trackTitle
            artistName = snapshot.artistName
            albumTitle = snapshot.albumTitle
            albumID = snapshot.albumID
            artworkImage = snapshot.artworkImage
            palette = snapshot.palette
            currentAlbum = snapshot.album
            currentArtist = snapshot.artist
            waveformLevels = snapshot.waveformLevels
        }
    }

    private func applyArtwork(image: UIImage?, palette: ArtworkPaletteTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            artworkImage = image
            self.palette = palette
        }
    }

    private func applyArtistAndWaveform(artist: Artist?, levels: [Float]?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentArtist = artist
            waveformLevels = levels
        }
    }

    // MARK: - Resolution helpers (shared by the live apply path and prefetch)

    /// Full-size album art + palette via the shared resolver, which fetches and
    /// decodes (downsampled, off the main actor) once per album and shares the
    /// result with the lock-screen bridge.
    private func resolveArtwork(track: Track, album: Album?) async -> (image: UIImage?, palette: ArtworkPaletteTheme) {
        guard let album else { return (nil, .default) }
        let art = await resolver.fullArtwork(for: album)
        return (art.image, art.palette)
    }

    private func resolveArtist(forName name: String) async -> Artist? {
        guard let artists = try? await library.searchArtists(query: name) else { return nil }
        return artists.first { $0.name == name }
    }

    private func resolveLoudness(plexID: String) async -> [Float]? {
        try? await library.fetchLoudnessLevels(trackID: plexID)
    }

    /// Builds a complete snapshot with all display data resolved (used by prefetch).
    /// The independent legs run concurrently. Returns nil if the task is cancelled.
    private func buildSnapshot(track: Track, album: Album?) async -> TrackSnapshot? {
        async let artistTask = resolveArtist(forName: track.artistName)
        async let levelsTask = resolveLoudness(plexID: track.plexID)

        let (image, palette) = await resolveArtwork(track: track, album: album)
        guard !Task.isCancelled else { return nil }

        let artist = await artistTask
        let levels = await levelsTask
        guard !Task.isCancelled else { return nil }

        return TrackSnapshot(
            trackTitle: track.title,
            artistName: track.artistName,
            albumTitle: album?.title,
            albumID: track.albumID,
            artworkImage: image,
            palette: palette,
            album: album,
            artist: artist,
            waveformLevels: levels
        )
    }

    // MARK: - Cache Eviction

    /// Keeps only the current and next track snapshots to prevent unbounded
    /// memory growth from full-size UIImages accumulating over a long session.
    private func evictStaleSnapshots() {
        let items = queueManager.items
        guard let currentIndex = queueManager.currentIndex,
              items.indices.contains(currentIndex) else {
            snapshotCache.removeAll()
            return
        }

        var keepIDs = Set<String>()
        keepIDs.insert(items[currentIndex].trackID)
        let nextIndex = currentIndex + 1
        if items.indices.contains(nextIndex) {
            keepIDs.insert(items[nextIndex].trackID)
        }

        for key in snapshotCache.keys where !keepIDs.contains(key) {
            snapshotCache.removeValue(forKey: key)
        }
    }

    // MARK: - Prefetch

    private func prefetchNextTrack() {
        guard let currentIndex = queueManager.currentIndex else { return }
        let items = queueManager.items
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else { return }

        let nextTrackID = items[nextIndex].trackID
        // Already cached or already in-flight — nothing to do.
        guard snapshotCache[nextTrackID] == nil,
              prefetchingTrackID != nextTrackID else { return }

        prefetchTask?.cancel()
        prefetchingTrackID = nextTrackID
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            guard let track = await self.resolver.track(id: nextTrackID) else { return }
            let album = await self.resolver.album(id: track.albumID)
            guard let snapshot = await self.buildSnapshot(track: track, album: album) else { return }
            guard !Task.isCancelled else { return }
            self.snapshotCache[nextTrackID] = snapshot
            self.prefetchingTrackID = nil
        }
    }

    // MARK: - Up Next Resolution

    private func resolveUpNextIfNeeded() {
        // Re-resolve on every queue change. A dedup keyed on (index, count) wrongly
        // suppressed a full queue REPLACE that preserved both (e.g. shuffling a new
        // artist onto the same index 0 with the same track count), leaving the prior
        // queue's tracks in Up Next until the index later moved (Lunara-rhp). The
        // queue only mutates on genuine changes — reconcile() never reassigns an
        // identical array — so there is no redundant work to guard against, and the
        // in-flight task is cancelled below.
        upNextTask?.cancel()
        // Runs at default priority: the heavy image work is already offloaded via
        // Task.detached, so this no longer hogs the main actor — and a lower QoS
        // here gets starved during active playback, leaving Up Next stale.
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

        let slice = Array(zip(startIndex..<endIndex, items[startIndex..<endIndex]))

        // Reuse rows already resolved for the same track (text + decoded thumbnail) so
        // an advance or a same-window re-trigger doesn't re-fetch/re-decode them. A row
        // that transiently failed last time stays as-is until its track leaves the
        // window — an accepted trade for avoiding a full 20-row rebuild every change.
        let existingByID = Dictionary(
            upNextItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Resolve and publish the first (visible) rows eagerly, then fill the long tail,
        // so a full replace/shuffle paints the top of Up Next without waiting on all 20.
        let eagerBound = min(Self.upNextEagerCount, slice.count)
        var resolved: [UpNextItem] = []
        resolved.reserveCapacity(slice.count)

        for (offset, (queueIndex, item)) in slice.enumerated() {
            guard !Task.isCancelled else { return }
            if let reused = existingByID[item.trackID] {
                // Carried over: keep the resolved text + decoded image, refresh position.
                resolved.append(UpNextItem(
                    id: reused.id,
                    queueIndex: queueIndex,
                    trackTitle: reused.trackTitle,
                    artistName: reused.artistName,
                    artworkImage: reused.artworkImage
                ))
            } else {
                resolved.append(await resolveUpNextRow(queueIndex: queueIndex, item: item))
            }

            // Publish the eager window the moment it's complete; the tail follows below.
            if offset == eagerBound - 1 {
                guard !Task.isCancelled else { return }
                upNextItems = resolved
            }
        }

        guard !Task.isCancelled else { return }
        upNextItems = resolved
    }

    /// Fully resolves one up-next row: track + album text and a downsampled thumbnail
    /// (decoded off the main actor). The track/album/thumbnail lookups are shared via
    /// the resolver; only the per-row downsample decode is unique to Up Next.
    private func resolveUpNextRow(queueIndex: Int, item: QueueItem) async -> UpNextItem {
        let track = await resolver.track(id: item.trackID)
        let thumbURL: URL?
        if let track, let album = await resolver.album(id: track.albumID) {
            thumbURL = await resolver.thumbnailURL(for: album)
        } else {
            thumbURL = nil
        }
        let thumbImage: UIImage?
        if let thumbURL {
            let pointSize = Self.upNextThumbnailPointSize
            let scale = displayScale
            thumbImage = await Task.detached {
                DownsamplingImageLoader.load(contentsOf: thumbURL, pointSize: pointSize, scale: scale)
            }.value
        } else {
            thumbImage = nil
        }
        return UpNextItem(
            id: item.trackID,
            queueIndex: queueIndex,
            trackTitle: track?.title ?? "Unknown Track",
            artistName: track?.artistName ?? "Unknown Artist",
            artworkImage: thumbImage
        )
    }
}
