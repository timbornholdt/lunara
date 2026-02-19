import Foundation

extension PlexAPIClient {
    /// Fetch metadata for a single track by Plex rating key.
    func fetchTrack(id trackID: String) async throws -> Track? {
        let endpoint = "/library/metadata/\(trackID)"
        let request = try await buildRequest(path: endpoint, requiresAuth: true)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        guard let metadata = try xmlDecoder
            .decode(PlexMediaContainer.self, from: data)
            .metadata?
            .first(where: { $0.type == "track" }) else {
            return nil
        }

        guard let albumID = metadata.parentRatingKey, !albumID.isEmpty else {
            throw LibraryError.invalidResponse
        }

        guard let key = metadata.key, key.hasPrefix("/library/parts/") else {
            throw LibraryError.invalidResponse
        }

        return Track(
            plexID: metadata.ratingKey,
            albumID: albumID,
            title: metadata.title,
            trackNumber: metadata.index ?? 0,
            duration: TimeInterval(metadata.duration ?? 0) / 1000.0,
            artistName: metadata.originalTitle ?? metadata.grandparentTitle ?? metadata.parentTitle ?? "Unknown Artist",
            key: key,
            thumbURL: metadata.thumb
        )
    }
}
