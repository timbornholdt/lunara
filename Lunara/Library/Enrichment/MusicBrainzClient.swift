import Foundation
import os

/// External catalog data for one artist: canonical links plus their studio-album
/// release groups (Lunara-uww.6.2 / 6.3).
struct MusicBrainzArtistEnrichment: Equatable, Sendable {
    let artistID: String
    let wikipediaURL: URL?
    let homepageURL: URL?
    let albums: [ExternalReleaseGroup]

    var musicBrainzURL: URL {
        URL(string: "https://musicbrainz.org/artist/\(artistID)")!
    }
}

/// One MusicBrainz release group (an "album" across all its editions).
/// Codable so the enrichment cache can persist discographies (Lunara-ya7).
struct ExternalReleaseGroup: Equatable, Sendable, Identifiable, Codable {
    let id: String
    let title: String
    let firstReleaseYear: Int?
    /// Raw MusicBrainz date ("yyyy", "yyyy-MM", or "yyyy-MM-dd") — future for
    /// announced-but-unreleased albums, which powers the radar (Lunara-nlo).
    let firstReleaseDate: String?

    init(id: String, title: String, firstReleaseYear: Int?, firstReleaseDate: String? = nil) {
        self.id = id
        self.title = title
        self.firstReleaseYear = firstReleaseYear
        self.firstReleaseDate = firstReleaseDate
    }

    var musicBrainzURL: URL {
        URL(string: "https://musicbrainz.org/release-group/\(id)")!
    }
}

protocol MusicBrainzClientProtocol: Sendable {
    /// Resolves an artist by name and returns links + studio-album discography,
    /// or nil when MusicBrainz has no confident match.
    func artistEnrichment(name: String) async throws -> MusicBrainzArtistEnrichment?

    /// Studio-album release groups for an artist — the lighter, links-free
    /// lookup the radar uses (2 requests vs enrichment's 3-4).
    func upcomingAlbums(artistName: String) async throws -> [ExternalReleaseGroup]

    /// Resolves an artist name to its MusicBrainz ID, or nil when there is no
    /// confident match. The radar caches the result so later sweeps skip this
    /// search request (Lunara-be2).
    func artistID(name: String) async throws -> String?

    /// Studio-album release groups by already-resolved MBID — one request
    /// instead of search + fetch.
    func upcomingAlbums(artistID: String) async throws -> [ExternalReleaseGroup]
}

// Defaults so conformers that don't serve the radar (and test mocks) need not
// implement the MBID-aware pair — same pattern as LibraryRepoProtocol.
extension MusicBrainzClientProtocol {
    func artistID(name: String) async throws -> String? { nil }
    func upcomingAlbums(artistID: String) async throws -> [ExternalReleaseGroup] { [] }
}

/// MusicBrainz needs no API key, but requires a descriptive User-Agent and
/// at most ~1 request/second — requests are throttled accordingly. Parsing is
/// in internal statics so it's unit-testable without networking.
actor MusicBrainzClient: MusicBrainzClientProtocol {
    private let session: URLSession
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "MusicBrainzClient")
    private var lastRequestTime: ContinuousClock.Instant?
    private static let userAgent = "Lunara/1.0 (https://github.com/timbornholdt/lunara)"
    /// Matches below this search score are more likely a different artist than a
    /// fuzzy spelling of this one — worse than returning nothing.
    private static let minimumSearchScore = 90

    init(session: URLSession = .shared) {
        self.session = session
    }

    func artistEnrichment(name: String) async throws -> MusicBrainzArtistEnrichment? {
        guard let artistID = try await searchArtistID(name: name) else { return nil }

        let relations = try Self.parseArtistRelations(
            await get("https://musicbrainz.org/ws/2/artist/\(artistID)", query: [
                "inc": "url-rels", "fmt": "json"
            ])
        )

        var wikipediaURL = relations.wikipediaURL
        if wikipediaURL == nil, let wikidataURL = relations.wikidataURL,
           let entityID = wikidataURL.pathComponents.last {
            wikipediaURL = try? Self.parseWikipediaURL(
                await get("https://www.wikidata.org/wiki/Special:EntityData/\(entityID).json", query: [:])
            )
        }

        let albums = try Self.parseReleaseGroups(
            await get("https://musicbrainz.org/ws/2/release-group", query: [
                "artist": artistID, "type": "album", "fmt": "json", "limit": "100"
            ])
        )

        return MusicBrainzArtistEnrichment(
            artistID: artistID,
            wikipediaURL: wikipediaURL,
            homepageURL: relations.homepageURL,
            albums: albums
        )
    }

    /// All studio-album release groups for the artist, full dates included; the
    /// caller filters for the future. Named for its radar role (Lunara-nlo).
    func upcomingAlbums(artistName: String) async throws -> [ExternalReleaseGroup] {
        guard let artistID = try await searchArtistID(name: artistName) else { return [] }
        return try await upcomingAlbums(artistID: artistID)
    }

    func artistID(name: String) async throws -> String? {
        try await searchArtistID(name: name)
    }

    func upcomingAlbums(artistID: String) async throws -> [ExternalReleaseGroup] {
        try Self.parseReleaseGroups(
            await get("https://musicbrainz.org/ws/2/release-group", query: [
                "artist": artistID, "type": "album", "fmt": "json", "limit": "100"
            ])
        )
    }

    private func searchArtistID(name: String) async throws -> String? {
        try Self.parseArtistSearch(
            await get("https://musicbrainz.org/ws/2/artist", query: [
                "query": "artist:\"\(name)\"", "fmt": "json", "limit": "3"
            ])
        )
    }

    private func get(_ urlString: String, query: [String: String]) async throws -> Data {
        var components = URLComponents(string: urlString)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw LibraryError.invalidResponse }

        await throttle()
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            logger.error("MusicBrainz request failed: \(url.absoluteString, privacy: .public)")
            throw LibraryError.invalidResponse
        }
        return data
    }

    /// Keeps at least one second between requests, per MusicBrainz rate policy.
    private func throttle() async {
        let now = ContinuousClock.now
        if let last = lastRequestTime {
            let elapsed = last.duration(to: now)
            if elapsed < .seconds(1) {
                try? await Task.sleep(for: .seconds(1) - elapsed)
            }
        }
        lastRequestTime = ContinuousClock.now
    }

    // MARK: - Parsing (internal statics, unit-tested)

    static func parseArtistSearch(_ data: Data) throws -> String? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artists = json["artists"] as? [[String: Any]],
              let top = artists.first,
              let id = top["id"] as? String,
              let score = top["score"] as? Int,
              score >= minimumSearchScore else {
            return nil
        }
        return id
    }

    struct ArtistRelations: Equatable {
        let wikidataURL: URL?
        let wikipediaURL: URL?
        let homepageURL: URL?
    }

    static func parseArtistRelations(_ data: Data) throws -> ArtistRelations {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let relations = json["relations"] as? [[String: Any]] else {
            return ArtistRelations(wikidataURL: nil, wikipediaURL: nil, homepageURL: nil)
        }

        func url(forType type: String) -> URL? {
            for relation in relations where (relation["type"] as? String) == type {
                if let resource = (relation["url"] as? [String: Any])?["resource"] as? String {
                    return URL(string: resource)
                }
            }
            return nil
        }

        return ArtistRelations(
            wikidataURL: url(forType: "wikidata"),
            wikipediaURL: url(forType: "wikipedia"),
            homepageURL: url(forType: "official homepage")
        )
    }

    static func parseWikipediaURL(_ data: Data) throws -> URL? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entities = json["entities"] as? [String: Any],
              let entity = entities.values.first as? [String: Any],
              let sitelinks = entity["sitelinks"] as? [String: Any],
              let enwiki = sitelinks["enwiki"] as? [String: Any],
              let title = enwiki["title"] as? String,
              let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
    }

    static func parseReleaseGroups(_ data: Data) throws -> [ExternalReleaseGroup] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = json["release-groups"] as? [[String: Any]] else {
            return []
        }

        return groups.compactMap { group in
            guard let id = group["id"] as? String,
                  let title = group["title"] as? String,
                  (group["primary-type"] as? String) == "Album",
                  (group["secondary-types"] as? [String] ?? []).isEmpty else {
                return nil
            }
            let rawDate = (group["first-release-date"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let year = rawDate.flatMap { Int($0.prefix(4)) }
            return ExternalReleaseGroup(id: id, title: title, firstReleaseYear: year, firstReleaseDate: rawDate)
        }
    }
}
