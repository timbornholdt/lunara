import Foundation
import os

// MARK: - PlexAPIClient

/// HTTP client for Plex Media Server API
/// Handles authentication, request building, and response parsing
final class PlexAPIClient: PlexAuthAPIProtocol {

    // MARK: - Properties

    private let baseURL: URL
    private let authManager: AuthManager
    private let session: URLSessionProtocol
    private let xmlDecoder: XMLDecoder
    private let jsonDecoder: JSONDecoder
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "PlexAPIClient")

    // Plex client identification headers (required by Plex API)
    private let clientIdentifier = "Lunara-iOS"
    private let productName = "Lunara"
    private let productVersion = "1.0"

    // MARK: - Initialization

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

    // MARK: - Library Methods

    /// Fetch all albums from the Plex library
    func fetchAlbums() async throws -> [Album] {
        let endpoint = "/library/sections/4/all"
        let request = try await buildRequest(
            path: endpoint,
            queryItems: [URLQueryItem(name: "type", value: "9")],
            requiresAuth: true
        )

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

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

            // Convert addedAt timestamp to Date
            let addedAtDate = directory.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }

            // Convert duration from milliseconds to seconds
            let durationSeconds = directory.duration.map { TimeInterval($0) / 1000.0 } ?? 0.0

            albums.append(Album(
                plexID: albumID,
                title: directory.title,
                artistName: directory.parentTitle ?? "Unknown Artist",
                year: directory.year,
                thumbURL: directory.thumb,
                genre: directory.genre,
                rating: directory.rating.map { Int($0) },
                addedAt: addedAtDate,
                trackCount: directory.leafCount ?? 0,
                duration: durationSeconds
            ))
        }

        return albums
    }

    /// Fetch tracks for a specific album
    /// - Parameter albumID: Plex rating key for the album
    func fetchTracks(forAlbum albumID: String) async throws -> [Track] {
        let endpoint = "/library/metadata/\(albumID)/children"
        let request = try await buildRequest(path: endpoint, requiresAuth: true)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

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
                artistName: plexMetadata.grandparentTitle ?? plexMetadata.parentTitle ?? "Unknown Artist",
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

    // MARK: - PlexAuthAPIProtocol (OAuth Methods)

    /// Request a new PIN for user authorization
    func requestPin() async throws -> PlexPinResponse {
        let url = URL(string: "https://plex.tv/api/v2/pins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addClientHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

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

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        // Parse XML response
        let parser = PlexPinXMLParser()
        guard let attributes = parser.parse(data: data),
              let authToken = attributes["authToken"] else {
            throw LibraryError.invalidResponse
        }

        // Empty string means not authorized yet
        return authToken.isEmpty ? nil : authToken
    }

    // MARK: - Private Helpers

    /// Build a URLRequest with proper headers and authentication
    private func buildRequest(
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
    private func validateResponse(_ response: URLResponse) throws {
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
}
