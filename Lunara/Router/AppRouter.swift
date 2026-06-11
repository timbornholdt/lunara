import Foundation
import os

struct QueueReconciliationOutcome: Equatable {
    let removedTrackIDs: [String]
    let removedItemCount: Int

    static let noChanges = QueueReconciliationOutcome(removedTrackIDs: [], removedItemCount: 0)
}

@MainActor
final class AppRouter {
    private let library: LibraryRepoProtocol
    private let queue: QueueManagerProtocol
    /// Opt-in queue-build span recorder (Lunara-lz4). Nil or disabled ⇒ zero work.
    private let telemetry: PlaybackTelemetryEmitting?
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "AppRouter")

    init(
        library: LibraryRepoProtocol,
        queue: QueueManagerProtocol,
        telemetry: PlaybackTelemetryEmitting? = nil
    ) {
        self.library = library
        self.queue = queue
        self.telemetry = telemetry
    }

    /// Times the tap→queue-built leg of a play intent and records it as a
    /// `queueBuild` detail record, so slow starts can be split between queue
    /// construction and track resolution/download (Lunara-lz4).
    private func timedQueueBuild(kind: String, _ build: () async throws -> [QueueItem]) async throws -> [QueueItem] {
        guard let telemetry, telemetry.isEnabled else {
            return try await build()
        }
        let clock = ContinuousClock()
        let start = clock.now
        let items = try await build()
        let duration = start.duration(to: clock.now)
        let ms = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        telemetry.recordDetail(eventName: "queueBuild", info: [
            "kind": kind,
            "items": String(items.count),
            "buildMs": String(format: "%.0f", ms)
        ])
        return items
    }

    func playAlbum(_ album: Album) async throws {
        logger.info("playAlbum started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = queueItems(forTracks: tracks)

        logEnqueueReport(album: album, tracks: tracks, items: items)
        queue.playNow(items)
        logger.info("playAlbum queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func queueAlbumNext(_ album: Album) async throws {
        logger.info("queueAlbumNext started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = queueItems(forTracks: tracks)
        queue.playNext(items)
        logger.info("queueAlbumNext queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func queueAlbumLater(_ album: Album) async throws {
        logger.info("queueAlbumLater started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = queueItems(forTracks: tracks)
        queue.playLater(items)
        logger.info("queueAlbumLater queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func playTrackNow(_ track: Track) async throws {
        queue.playNow(queueItems(forTracks: [track]))
    }

    func playTracksNow(_ tracks: [Track]) async throws {
        queue.playNow(queueItems(forTracks: tracks))
    }

    func queueTrackNext(_ track: Track) async throws {
        queue.playNext(queueItems(forTracks: [track]))
    }

    func queueTrackLater(_ track: Track) async throws {
        queue.playLater(queueItems(forTracks: [track]))
    }

    func playPlaylist(_ playlist: Playlist) async throws {
        logger.info("playPlaylist started for playlist '\(playlist.title, privacy: .public)' id '\(playlist.plexID, privacy: .public)'")
        let items = try await timedQueueBuild(kind: "playPlaylist") { try await self.allQueueItemsForPlaylist(playlist) }
        queue.playNow(items)
        logger.info("playPlaylist queued \(items.count, privacy: .public) items for playlist id '\(playlist.plexID, privacy: .public)'")
    }

    func shufflePlaylist(_ playlist: Playlist) async throws {
        logger.info("shufflePlaylist started for playlist '\(playlist.title, privacy: .public)' id '\(playlist.plexID, privacy: .public)'")
        let items = try await timedQueueBuild(kind: "shufflePlaylist") { try await self.allQueueItemsForPlaylist(playlist) }
        queue.playNow(items.shuffled())
        logger.info("shufflePlaylist queued \(items.count, privacy: .public) shuffled items for playlist id '\(playlist.plexID, privacy: .public)'")
    }

    func playCollection(_ collection: Collection) async throws {
        logger.info("playCollection started for collection '\(collection.title, privacy: .public)' id '\(collection.plexID, privacy: .public)'")
        let items = try await timedQueueBuild(kind: "playCollection") { try await self.allQueueItemsForCollection(collection) }
        queue.playNow(items)
        logger.info("playCollection queued \(items.count, privacy: .public) items for collection id '\(collection.plexID, privacy: .public)'")
    }

    func shuffleCollection(_ collection: Collection) async throws {
        logger.info("shuffleCollection started for collection '\(collection.title, privacy: .public)' id '\(collection.plexID, privacy: .public)'")
        let items = try await timedQueueBuild(kind: "shuffleCollection") { try await self.allQueueItemsForCollection(collection) }
        queue.playNow(items.shuffled())
        logger.info("shuffleCollection queued \(items.count, privacy: .public) shuffled items for collection id '\(collection.plexID, privacy: .public)'")
    }

    func playArtist(_ artist: Artist) async throws {
        logger.info("playArtist started for artist '\(artist.name, privacy: .public)' id '\(artist.plexID, privacy: .public)'")
        let items = try await timedQueueBuild(kind: "playArtist") { try await self.allQueueItemsForArtist(artist) }
        queue.playNow(items)
        logger.info("playArtist queued \(items.count, privacy: .public) items for artist id '\(artist.plexID, privacy: .public)'")
    }

    func shuffleArtist(_ artist: Artist) async throws {
        logger.info("shuffleArtist started for artist '\(artist.name, privacy: .public)' id '\(artist.plexID, privacy: .public)'")
        let items = try await timedQueueBuild(kind: "shuffleArtist") { try await self.allQueueItemsForArtist(artist) }
        queue.playNow(items.shuffled())
        logger.info("shuffleArtist queued \(items.count, privacy: .public) shuffled items for artist id '\(artist.plexID, privacy: .public)'")
    }

    func playAlbums(_ albums: [Album]) async throws {
        logger.info("playAlbums started for \(albums.count, privacy: .public) albums")
        let items = try await timedQueueBuild(kind: "playAlbums") { try await self.allQueueItemsForAlbums(albums) }
        queue.playNow(items)
        logger.info("playAlbums queued \(items.count, privacy: .public) items")
    }

    func shuffleAlbums(_ albums: [Album]) async throws {
        logger.info("shuffleAlbums started for \(albums.count, privacy: .public) albums")
        let items = try await timedQueueBuild(kind: "shuffleAlbums") { try await self.allQueueItemsForAlbums(albums) }
        queue.playNow(items.shuffled())
        logger.info("shuffleAlbums queued \(items.count, privacy: .public) shuffled items")
    }

    func shuffleAllAlbums() async throws {
        logger.info("shuffleAllAlbums started")
        let items = try await timedQueueBuild(kind: "shuffleAllAlbums") {
            let albums = try await self.library.fetchAlbums()
            return try await self.allQueueItemsForAlbums(albums)
        }
        guard !items.isEmpty else {
            throw LibraryError.resourceNotFound(type: "tracks", id: "all")
        }
        queue.playNow(items.shuffled())
        logger.info("shuffleAllAlbums queued \(items.count, privacy: .public) shuffled items")
    }

    func pausePlayback() {
        queue.pause()
    }

    func resumePlayback() {
        queue.resume()
    }

    func skipToNextTrack() {
        queue.skipToNext()
    }

    func stopPlayback() {
        queue.clear()
    }

    func reconcileQueueAgainstLibrary() async throws -> QueueReconciliationOutcome {
        let queuedItems = queue.items
        guard !queuedItems.isEmpty else {
            return .noChanges
        }

        var missingTrackIDs: Set<String> = []
        var trackLookupCache: [String: Bool] = [:]
        trackLookupCache.reserveCapacity(queuedItems.count)

        for item in queuedItems {
            if let isPresent = trackLookupCache[item.trackID] {
                if !isPresent {
                    missingTrackIDs.insert(item.trackID)
                }
                continue
            }

            let track = try await library.track(id: item.trackID)
            let isPresent = track != nil
            trackLookupCache[item.trackID] = isPresent
            if !isPresent {
                missingTrackIDs.insert(item.trackID)
            }
        }

        guard !missingTrackIDs.isEmpty else {
            return .noChanges
        }

        let removedItemCount = queuedItems.filter { missingTrackIDs.contains($0.trackID) }.count
        queue.reconcile(removingTrackIDs: missingTrackIDs)
        let sortedMissingTrackIDs = missingTrackIDs.sorted()
        logger.info(
            "Queue reconciliation removed \(removedItemCount, privacy: .public) items for missing track IDs: \(sortedMissingTrackIDs.joined(separator: ","), privacy: .public)"
        )
        return QueueReconciliationOutcome(
            removedTrackIDs: sortedMissingTrackIDs,
            removedItemCount: removedItemCount
        )
    }

    private func allQueueItemsForPlaylist(_ playlist: Playlist) async throws -> [QueueItem] {
        let playlistItems = try await library.playlistItems(playlistID: playlist.plexID)
        guard !playlistItems.isEmpty else {
            logger.error("Found zero items for playlist id '\(playlist.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: playlist.plexID)
        }

        var tracks: [Track] = []
        tracks.reserveCapacity(playlistItems.count)
        for item in playlistItems {
            guard let track = try await library.track(id: item.trackID) else {
                logger.warning("Playlist item trackID '\(item.trackID, privacy: .public)' not found in library, skipping")
                continue
            }
            tracks.append(track)
        }

        let queueItems = queueItems(forTracks: tracks)
        guard !queueItems.isEmpty else {
            logger.error("No resolvable tracks for playlist id '\(playlist.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: playlist.plexID)
        }

        return queueItems
    }

    private func allQueueItemsForCollection(_ collection: Collection) async throws -> [QueueItem] {
        let albums = try await library.collectionAlbums(collectionID: collection.plexID)
        guard !albums.isEmpty else {
            logger.error("Found zero albums for collection id '\(collection.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "albums", id: collection.plexID)
        }
        let items = try await allQueueItemsForAlbums(albums)
        guard !items.isEmpty else {
            logger.error("Found zero tracks across \(albums.count, privacy: .public) albums for collection id '\(collection.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: collection.plexID)
        }
        return items
    }

    private func allQueueItemsForArtist(_ artist: Artist) async throws -> [QueueItem] {
        let albums = try await library.artistAlbums(artistName: artist.name)
        guard !albums.isEmpty else {
            logger.error("Found zero albums for artist id '\(artist.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "albums", id: artist.plexID)
        }
        let items = try await allQueueItemsForAlbums(albums)
        guard !items.isEmpty else {
            logger.error("Found zero tracks across \(albums.count, privacy: .public) albums for artist id '\(artist.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: artist.plexID)
        }
        return items
    }

    private func allQueueItemsForAlbums(_ albums: [Album]) async throws -> [QueueItem] {
        var allTracks: [Track] = []
        for album in albums {
            let tracks = try await library.tracks(forAlbum: album.plexID)
            allTracks.append(contentsOf: tracks)
        }
        guard !allTracks.isEmpty else { return [] }
        return queueItems(forTracks: allTracks)
    }

    /// Builds queue items from stable identifiers only. The playable URL is
    /// resolved lazily at play time (see PlaybackURLResolver), never baked in here.
    private func queueItems(forTracks tracks: [Track]) -> [QueueItem] {
        tracks.map { track in
            QueueItem(
                trackID: track.plexID,
                streamKey: track.key,
                albumID: track.albumID,
                trackNumber: track.trackNumber,
                duration: track.duration
            )
        }
    }

    private func tracks(forAlbum album: Album) async throws -> [Track] {
        let tracks: [Track]
        do {
            tracks = try await library.tracks(forAlbum: album.plexID)
        } catch {
            logger.error("Failed to fetch tracks for album id '\(album.plexID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }

        logger.info("Fetched \(tracks.count, privacy: .public) tracks for album id '\(album.plexID, privacy: .public)'")
        guard !tracks.isEmpty else {
            logger.error("Found zero tracks for album id '\(album.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: album.plexID)
        }

        return tracks
    }

    private func logEnqueueReport(album: Album, tracks: [Track], items: [QueueItem]) {
        var tracksByID: [String: Track] = [:]
        tracksByID.reserveCapacity(tracks.count)
        for track in tracks {
            tracksByID[track.plexID] = track
        }

        var lines: [String] = []
        lines.append("========== LUNARA PLAY ALBUM ENQUEUE REPORT ==========")
        lines.append("albumTitle=\(album.title)")
        lines.append("albumID=\(album.plexID)")
        lines.append("trackCount=\(tracks.count)")
        lines.append("queuedCount=\(items.count)")

        for (index, item) in items.enumerated() {
            guard let track = tracksByID[item.trackID] else {
                lines.append("[\(index + 1)] trackID=\(item.trackID) missing-track-metadata streamKey=\(item.streamKey)")
                continue
            }

            lines.append(
                "[\(index + 1)] trackNumber=\(track.trackNumber) trackID=\(track.plexID) title=\(track.title) duration=\(Int(track.duration))s key=\(track.key)"
            )
        }

        lines.append("======================================================")
        logger.info("\(lines.joined(separator: "\n"), privacy: .public)")
    }
}
