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
    private let library: LibraryRepoProtocol
    private let artworkPipeline: ArtworkPipelineProtocol

    // MARK: - Private State

    private var resolvedTrackID: String?
    private var resolvedUpNextIndex: Int?
    private var resolvedUpNextCount: Int?
    private var metadataTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchingTrackID: String?
    private var upNextTask: Task<Void, Never>?
    private var snapshotCache: [String: TrackSnapshot] = [:]

    /// Rendered size of an up-next row thumbnail; artwork is downsampled to this.
    private static let upNextThumbnailPointSize = CGSize(width: 40, height: 40)
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
        artworkPipeline: ArtworkPipelineProtocol
    ) {
        self.queueManager = queueManager
        self.engine = engine
        self.library = library
        self.artworkPipeline = artworkPipeline

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
        guard let track = try? await library.track(id: trackID) else { return }
        guard !Task.isCancelled else { return }
        let album = try? await library.album(id: track.albumID)
        guard !Task.isCancelled else { return }
        applyTextClearingVisuals(track: track, album: album)

        // Phase 2 — resolve artwork, palette, artist and waveform (slow: network
        // fetch + off-main decode) and apply them once ready.
        guard let snapshot = await buildSnapshot(track: track, album: album) else { return }
        guard !Task.isCancelled else { return }
        snapshotCache[trackID] = snapshot
        applySnapshot(snapshot)
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

    /// Builds a complete snapshot with all display data resolved. The CPU-heavy
    /// image decode + palette extraction run off the main actor. Returns nil if the
    /// task is cancelled.
    private func buildSnapshot(track: Track, album: Album?) async -> TrackSnapshot? {
        // Resolve artist
        let artist: Artist?
        if let artists = try? await library.searchArtists(query: track.artistName) {
            artist = artists.first { $0.name == track.artistName }
        } else {
            artist = nil
        }
        guard !Task.isCancelled else { return nil }

        // Fetch full-size artwork source
        let sourceURL: URL?
        if let album {
            sourceURL = try? await library.authenticatedArtworkURL(for: album.thumbURL)
        } else {
            sourceURL = nil
        }

        let fileURL = try? await artworkPipeline.fetchFullSize(
            for: track.albumID,
            ownerKind: .album,
            sourceURL: sourceURL
        )
        guard !Task.isCancelled else { return nil }

        // Decode the image and extract its palette OFF the main actor (both are
        // CPU-heavy and would otherwise stall the UI / starve other resolution).
        let decoded: (image: UIImage?, palette: ArtworkPaletteTheme) = await Task.detached {
            if let fileURL, let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
                return (img, ArtworkPaletteExtractor.extract(from: img))
            }
            return (nil, .default)
        }.value
        guard !Task.isCancelled else { return nil }

        // Fetch waveform loudness levels
        let levels = try? await library.fetchLoudnessLevels(trackID: track.plexID)
        guard !Task.isCancelled else { return nil }

        return TrackSnapshot(
            trackTitle: track.title,
            artistName: track.artistName,
            albumTitle: album?.title,
            albumID: track.albumID,
            artworkImage: decoded.image,
            palette: decoded.palette,
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
            guard let track = try? await self.library.track(id: nextTrackID) else { return }
            let album = try? await self.library.album(id: track.albumID)
            guard let snapshot = await self.buildSnapshot(track: track, album: album) else { return }
            guard !Task.isCancelled else { return }
            self.snapshotCache[nextTrackID] = snapshot
            self.prefetchingTrackID = nil
        }
    }

    // MARK: - Up Next Resolution

    private func resolveUpNextIfNeeded() {
        let newIndex = queueManager.currentIndex
        let newCount = queueManager.items.count
        guard newIndex != resolvedUpNextIndex || newCount != resolvedUpNextCount else { return }
        resolvedUpNextIndex = newIndex
        resolvedUpNextCount = newCount

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
        var resolved: [UpNextItem] = []

        for (queueIndex, item) in slice {
            guard !Task.isCancelled else { return }
            let track = try? await library.track(id: item.trackID)
            let albumID = track?.albumID ?? item.trackID
            let sourceURL: URL?
            if let track, let album = try? await library.album(id: track.albumID) {
                sourceURL = try? await library.authenticatedThumbnailURL(for: album.thumbURL)
            } else {
                sourceURL = nil
            }
            let thumbURL = try? await artworkPipeline.fetchThumbnail(
                for: albumID,
                ownerKind: .album,
                sourceURL: sourceURL
            )
            let thumbImage: UIImage?
            if let thumbURL {
                let pointSize = Self.upNextThumbnailPointSize
                let scale = displayScale
                // Downsample off the main actor (CPU-heavy, runs up to 20× per refresh).
                thumbImage = await Task.detached {
                    DownsamplingImageLoader.load(contentsOf: thumbURL, pointSize: pointSize, scale: scale)
                }.value
            } else {
                thumbImage = nil
            }
            resolved.append(UpNextItem(
                id: item.trackID,
                queueIndex: queueIndex,
                trackTitle: track?.title ?? "Unknown Track",
                artistName: track?.artistName ?? "Unknown Artist",
                artworkImage: thumbImage
            ))
        }

        guard !Task.isCancelled else { return }
        upNextItems = resolved
    }
}
