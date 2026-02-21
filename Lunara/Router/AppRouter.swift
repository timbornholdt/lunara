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
    private let offlineStore: OfflineStoreProtocol?
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "AppRouter")

    init(library: LibraryRepoProtocol, queue: QueueManagerProtocol, offlineStore: OfflineStoreProtocol? = nil) {
        self.library = library
        self.queue = queue
        self.offlineStore = offlineStore
    }

    func resolveURL(for track: Track) async throws -> URL {
        if let offlineStore, let localURL = try await offlineStore.localFileURL(forTrackID: track.plexID) {
            return localURL
        }
        return try await library.streamURL(for: track)
    }

    func playAlbum(_ album: Album) async throws {
        logger.info("playAlbum started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = try await queueItems(for: tracks, actionName: "playAlbum")

        logEnqueueReport(album: album, tracks: tracks, items: items)
        queue.playNow(items)
        logger.info("playAlbum queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func queueAlbumNext(_ album: Album) async throws {
        logger.info("queueAlbumNext started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = try await queueItems(for: tracks, actionName: "queueAlbumNext")
        queue.playNext(items)
        logger.info("queueAlbumNext queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func queueAlbumLater(_ album: Album) async throws {
        logger.info("queueAlbumLater started for album '\(album.title, privacy: .public)' id '\(album.plexID, privacy: .public)'")
        let tracks = try await tracks(forAlbum: album)
        let items = try await queueItems(for: tracks, actionName: "queueAlbumLater")
        queue.playLater(items)
        logger.info("queueAlbumLater queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
    }

    func playTrackNow(_ track: Track) async throws {
        let item = try await queueItem(for: track, actionName: "playTrackNow")
        queue.playNow([item])
    }

    func queueTrackNext(_ track: Track) async throws {
        let item = try await queueItem(for: track, actionName: "queueTrackNext")
        queue.playNext([item])
    }

    func queueTrackLater(_ track: Track) async throws {
        let item = try await queueItem(for: track, actionName: "queueTrackLater")
        queue.playLater([item])
    }

    func playCollection(_ collection: Collection) async throws {
        logger.info("playCollection started for collection '\(collection.title, privacy: .public)' id '\(collection.plexID, privacy: .public)'")
        let items = try await allQueueItemsForCollection(collection)
        queue.playNow(items)
        logger.info("playCollection queued \(items.count, privacy: .public) items for collection id '\(collection.plexID, privacy: .public)'")
    }

    func shuffleCollection(_ collection: Collection) async throws {
        logger.info("shuffleCollection started for collection '\(collection.title, privacy: .public)' id '\(collection.plexID, privacy: .public)'")
        let items = try await allQueueItemsForCollection(collection)
        queue.playNow(items.shuffled())
        logger.info("shuffleCollection queued \(items.count, privacy: .public) shuffled items for collection id '\(collection.plexID, privacy: .public)'")
    }

    func playArtist(_ artist: Artist) async throws {
        logger.info("playArtist started for artist '\(artist.name, privacy: .public)' id '\(artist.plexID, privacy: .public)'")
        let items = try await allQueueItemsForArtist(artist)
        queue.playNow(items)
        logger.info("playArtist queued \(items.count, privacy: .public) items for artist id '\(artist.plexID, privacy: .public)'")
    }

    func shuffleArtist(_ artist: Artist) async throws {
        logger.info("shuffleArtist started for artist '\(artist.name, privacy: .public)' id '\(artist.plexID, privacy: .public)'")
        let items = try await allQueueItemsForArtist(artist)
        queue.playNow(items.shuffled())
        logger.info("shuffleArtist queued \(items.count, privacy: .public) shuffled items for artist id '\(artist.plexID, privacy: .public)'")
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

    private func allQueueItemsForCollection(_ collection: Collection) async throws -> [QueueItem] {
        let albums = try await library.collectionAlbums(collectionID: collection.plexID)
        guard !albums.isEmpty else {
            logger.error("Found zero albums for collection id '\(collection.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "albums", id: collection.plexID)
        }

        let allItems = try await allQueueItemsForAlbums(albums, actionName: "collection-\(collection.plexID)")

        guard !allItems.isEmpty else {
            logger.error("Found zero tracks across \(albums.count, privacy: .public) albums for collection id '\(collection.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: collection.plexID)
        }

        return allItems
    }

    private func allQueueItemsForArtist(_ artist: Artist) async throws -> [QueueItem] {
        let albums = try await library.artistAlbums(artistName: artist.name)
        guard !albums.isEmpty else {
            logger.error("Found zero albums for artist id '\(artist.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "albums", id: artist.plexID)
        }

        let allItems = try await allQueueItemsForAlbums(albums, actionName: "artist-\(artist.plexID)")

        guard !allItems.isEmpty else {
            logger.error("Found zero tracks across \(albums.count, privacy: .public) albums for artist id '\(artist.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: artist.plexID)
        }

        return allItems
    }

    private func allQueueItemsForAlbums(_ albums: [Album], actionName: String) async throws -> [QueueItem] {
        var allItems: [QueueItem] = []
        for album in albums {
            let tracks = try await library.tracks(forAlbum: album.plexID)
            let items = try await queueItems(for: tracks, actionName: actionName)
            allItems.append(contentsOf: items)
        }
        return allItems
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

    private func queueItems(for tracks: [Track], actionName: String) async throws -> [QueueItem] {
        var items: [QueueItem] = []
        items.reserveCapacity(tracks.count)
        for track in tracks {
            items.append(try await queueItem(for: track, actionName: actionName))
        }
        return items
    }

    private func queueItem(for track: Track, actionName: String) async throws -> QueueItem {
        let url: URL
        do {
            url = try await resolveURL(for: track)
        } catch {
            logger.error(
                "\(actionName, privacy: .public) failed to resolve URL for track id '\(track.plexID, privacy: .public)' key '\(track.key, privacy: .public)': \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
        return QueueItem(trackID: track.plexID, url: url)
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
                lines.append("[\(index + 1)] trackID=\(item.trackID) missing-track-metadata url=\(sanitizeURL(item.url))")
                continue
            }

            lines.append(
                "[\(index + 1)] trackNumber=\(track.trackNumber) trackID=\(track.plexID) title=\(track.title) duration=\(Int(track.duration))s key=\(track.key) url=\(sanitizeURL(item.url))"
            )
        }

        lines.append("======================================================")
        logger.info("\(lines.joined(separator: "\n"), privacy: .public)")
    }

    private func sanitizeURL(_ url: URL) -> String {
        guard let host = url.host else {
            return url.path.isEmpty ? url.absoluteString : url.path
        }

        if url.path.isEmpty {
            return host
        }

        return host + url.path
    }
}
