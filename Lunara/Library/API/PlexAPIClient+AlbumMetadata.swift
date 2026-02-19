import Foundation

extension PlexAPIClient {
    /// Fetch detailed metadata for a single album.
    func fetchAlbum(id albumID: String) async throws -> Album? {
        let endpoint = "/library/metadata/\(albumID)"
        let request = try await buildRequest(path: endpoint, requiresAuth: true)

        let (data, _) = try await executeLoggedRequest(request, operation: "fetchAlbum[\(albumID)]")

        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        guard let directory = container.directories?.first(where: { $0.type == "album" }) else {
            return nil
        }

        let addedAtDate = directory.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let durationSeconds = directory.duration.map { TimeInterval($0) / 1000.0 } ?? 0.0
        let resolvedGenres = dedupedTags(directory.genres + [directory.genre].compactMap { $0 })

        return Album(
            plexID: directory.ratingKey ?? albumID,
            title: directory.title,
            artistName: directory.parentTitle ?? "Unknown Artist",
            year: directory.year,
            thumbURL: directory.thumb,
            genre: resolvedGenres.first,
            rating: directory.rating.map { Int($0) },
            addedAt: addedAtDate,
            trackCount: directory.leafCount ?? 0,
            duration: durationSeconds,
            review: directory.summary,
            genres: resolvedGenres,
            styles: dedupedTags(directory.styles),
            moods: dedupedTags(directory.moods)
        )
    }

    func dedupedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var deduped: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }
            deduped.append(trimmed)
        }
        return deduped
    }
}
