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
        let tracks: [Track]
        do {
            tracks = try await library.tracks(forAlbum: album.plexID)
        } catch {
            logger.error("playAlbum failed to fetch tracks for album id '\(album.plexID, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }

        logger.info("playAlbum fetched \(tracks.count, privacy: .public) tracks for album id '\(album.plexID, privacy: .public)'")
        guard !tracks.isEmpty else {
            logger.error("playAlbum found zero tracks for album id '\(album.plexID, privacy: .public)'")
            throw LibraryError.resourceNotFound(type: "tracks", id: album.plexID)
        }

        var items: [QueueItem] = []
        items.reserveCapacity(tracks.count)

        for track in tracks {
            let url: URL
            do {
                url = try await resolveURL(for: track)
            } catch {
                logger.error(
                    "playAlbum failed to resolve URL for track id '\(track.plexID, privacy: .public)' key '\(track.key, privacy: .public)': \(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
            items.append(QueueItem(trackID: track.plexID, url: url))
        }

        logEnqueueReport(album: album, tracks: tracks, items: items)
        queue.playNow(items)
        logger.info("playAlbum queued \(items.count, privacy: .public) items for album id '\(album.plexID, privacy: .public)'")
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
