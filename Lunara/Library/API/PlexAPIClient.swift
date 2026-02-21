import Foundation
import os

/// HTTP client for Plex Media Server API
/// Handles authentication, request building, and response parsing
final class PlexAPIClient: PlexAuthAPIProtocol {
    private let baseURL: URL
    private let authManager: AuthManager
    let session: URLSessionProtocol
    let xmlDecoder: XMLDecoder
    private let jsonDecoder: JSONDecoder
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "PlexAPIClient")

    // Plex client identification headers (required by Plex API)
    private let clientIdentifier = "Lunara-iOS"
    private let productName = "Lunara"
    private let productVersion = "1.0"

    /// Creates a PlexAPIClient
    /// - Parameters:
    ///   - baseURL: Base URL of Plex server (e.g., "http://192.168.1.100:32400")
    ///   - authManager: AuthManager for token retrieval
    ///   - session: URLSession (injectable for testing)
    init(
        baseURL: URL,
        authManager: AuthManager,
        session: URLSessionProtocol = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.authManager = authManager
        self.session = session
        self.xmlDecoder = XMLDecoder()
        self.jsonDecoder = JSONDecoder()
    }

    /// Fetch all albums from the Plex library
    func fetchAlbums() async throws -> [Album] {
        let endpoint = "/library/sections/4/all"
        let request = try await buildRequest(
            path: endpoint,
            queryItems: [URLQueryItem(name: "type", value: "9")],
            requiresAuth: true
        )

        let (data, _) = try await executeLoggedRequest(request, operation: "fetchAlbums")

        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        guard let directories = container.directories else {
            return []
        }

        var albums: [Album] = []
        albums.reserveCapacity(directories.count)

        for directory in directories {
            guard directory.type == "album" else { continue }
            guard let albumID = directory.ratingKey, !albumID.isEmpty else {
                logger.error(
                    "Album directory missing required ratingKey. title='\(directory.title, privacy: .public)' key='\(directory.key, privacy: .public)'"
                )
                throw LibraryError.invalidResponse
            }

            let addedAtDate = directory.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let durationSeconds = directory.duration.map { TimeInterval($0) / 1000.0 } ?? 0.0
            let resolvedGenres = dedupedTags(directory.genres + [directory.genre].compactMap { $0 })

            albums.append(Album(
                plexID: albumID,
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
            ))
        }

        return albums
    }

    /// Fetch tracks for a specific album
    /// - Parameter albumID: Plex rating key for the album
    func fetchTracks(forAlbum albumID: String) async throws -> [Track] {
        let endpoint = "/library/metadata/\(albumID)/children"
        let request = try await buildRequest(path: endpoint, requiresAuth: true)

        let (data, _) = try await executeLoggedRequest(request, operation: "fetchTracks[\(albumID)]")

        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        guard let metadata = container.metadata else {
            return []
        }

        var tracks: [Track] = []
        tracks.reserveCapacity(metadata.count)

        for plexMetadata in metadata {
            guard plexMetadata.type == "track" else { continue }
            guard let key = plexMetadata.key, key.hasPrefix("/library/parts/") else {
                logger.error(
                    "Track missing playable part key. albumID='\(albumID, privacy: .public)' trackID='\(plexMetadata.ratingKey, privacy: .public)' key='\(plexMetadata.key ?? "nil", privacy: .public)'"
                )
                throw LibraryError.invalidResponse
            }

            tracks.append(Track(
                plexID: plexMetadata.ratingKey,
                albumID: albumID,
                title: plexMetadata.title,
                trackNumber: plexMetadata.index ?? 0,
                duration: TimeInterval(plexMetadata.duration ?? 0) / 1000.0,
                artistName: plexMetadata.originalTitle ?? plexMetadata.grandparentTitle ?? plexMetadata.parentTitle ?? "Unknown Artist",
                key: key,
                thumbURL: plexMetadata.thumb
            ))
        }

        return tracks
    }

    /// Get streaming URL for a track
    /// - Parameter track: The track to stream
    /// - Returns: Direct play URL for the track
    func streamURL(forTrack track: Track) async throws -> URL {
        let token = try await authManager.validToken()
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = track.key
        components.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components.url else {
            throw LibraryError.invalidResponse
        }

        return url
    }

    func authenticatedArtworkURL(for rawValue: String?) async throws -> URL? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let token = try await authManager.validToken()

        let initialURL: URL?
        if let parsed = URL(string: rawValue), parsed.scheme != nil {
            initialURL = parsed
        } else if rawValue.hasPrefix("/") {
            initialURL = URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
        } else {
            initialURL = URL(string: "/\(rawValue)", relativeTo: baseURL)?.absoluteURL
        }

        guard let resolvedURL = initialURL else {
            return nil
        }

        guard var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "X-Plex-Token" }) {
            queryItems.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }
        components.queryItems = queryItems
        return components.url
    }

    /// Request a new PIN for user authorization
    func requestPin() async throws -> PlexPinResponse {
        let url = URL(string: "https://plex.tv/api/v2/pins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addClientHeaders(to: &request)

        let (data, _) = try await executeLoggedRequest(request, operation: "requestPin")

        // Parse XML response
        let parser = PlexPinXMLParser()
        guard let attributes = parser.parse(data: data),
              let idString = attributes["id"],
              let id = Int(idString),
              let code = attributes["code"] else {
            throw LibraryError.invalidResponse
        }

        return PlexPinResponse(id: id, code: code)
    }

    /// Check if user has authorized the PIN
    /// - Parameter pinID: The pin ID from requestPin()
    /// - Returns: Auth token if authorized, nil if still waiting
    func checkPin(pinID: Int) async throws -> String? {
        let url = URL(string: "https://plex.tv/api/v2/pins/\(pinID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addClientHeaders(to: &request)

        let (data, _) = try await executeLoggedRequest(request, operation: "checkPin[\(pinID)]")

        // Parse XML response
        let parser = PlexPinXMLParser()
        guard let attributes = parser.parse(data: data),
              let authToken = attributes["authToken"] else {
            throw LibraryError.invalidResponse
        }

        // Empty string means not authorized yet
        return authToken.isEmpty ? nil : authToken
    }

    /// Build a URLRequest with proper headers and authentication
    func buildRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        requiresAuth: Bool
    ) async throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        var mergedQueryItems = queryItems

        // Add auth token as query parameter if required
        if requiresAuth {
            let token = try await authManager.validToken()
            mergedQueryItems.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }

        if !mergedQueryItems.isEmpty {
            components.queryItems = mergedQueryItems
        }

        guard let url = components.url else {
            throw LibraryError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addClientHeaders(to: &request)

        return request
    }

    /// Add Plex client identification headers
    private func addClientHeaders(to request: inout URLRequest) {
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(productVersion, forHTTPHeaderField: "X-Plex-Version")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
    }

    /// Validate HTTP response and handle errors
    func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LibraryError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            // Token is invalid - tell AuthManager
            authManager.invalidateToken()
            throw LibraryError.authExpired
        case 404:
            throw LibraryError.resourceNotFound(type: "resource", id: "unknown")
        case 408, 504:
            throw LibraryError.timeout
        default:
            let message = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw LibraryError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    func executeLoggedRequest(
        _ request: URLRequest,
        operation: String
    ) async throws -> (Data, URLResponse) {
        let startedAt = Date()
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "unknown"
        logger.info("network start op=\(operation, privacy: .public) method=\(method, privacy: .public) path=\(path, privacy: .public)")

        do {
            let (data, response) = try await session.data(for: request)
            let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
            if let httpResponse = response as? HTTPURLResponse {
                logger.info(
                    "network response op=\(operation, privacy: .public) status=\(httpResponse.statusCode) bytes=\(data.count) durationMS=\(elapsedMS)"
                )
            } else {
                logger.info(
                    "network response op=\(operation, privacy: .public) nonHTTP=true bytes=\(data.count) durationMS=\(elapsedMS)"
                )
            }

            try validateResponse(response)
            logger.info("network success op=\(operation, privacy: .public)")
            return (data, response)
        } catch {
            let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
            logger.error(
                "network failure op=\(operation, privacy: .public) method=\(method, privacy: .public) path=\(path, privacy: .public) durationMS=\(elapsedMS) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

}
