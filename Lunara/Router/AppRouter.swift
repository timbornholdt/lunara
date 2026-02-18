import Foundation
import os

@MainActor
final class AppRouter {
    private let library: LibraryRepoProtocol
    private let queue: QueueManagerProtocol
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "AppRouter")

    init(library: LibraryRepoProtocol, queue: QueueManagerProtocol) {
        self.library = library
        self.queue = queue
    }

    func resolveURL(for track: Track) async throws -> URL {
        try await library.streamURL(for: track)
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
