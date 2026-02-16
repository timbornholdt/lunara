import Foundation

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
        let endpoint = "/library/sections/1/all"
        let request = try await buildRequest(path: endpoint, requiresAuth: true)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let container = try xmlDecoder.decode(PlexMediaContainer.self, from: data)
        guard let metadata = container.metadata else {
            return []
        }

        return metadata.compactMap { plexMetadata in
            guard plexMetadata.type == "album" else { return nil }
            return Album(
                plexID: plexMetadata.ratingKey,
                title: plexMetadata.title,
                artistName: plexMetadata.parentTitle ?? "Unknown Artist",
                year: plexMetadata.year,
                thumbURL: plexMetadata.thumb,
                genre: plexMetadata.genre,
                rating: plexMetadata.rating.map { Int($0) },
                addedAt: plexMetadata.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                trackCount: plexMetadata.trackCount ?? 0,
                duration: TimeInterval(plexMetadata.duration ?? 0) / 1000.0 // Plex returns milliseconds
            )
        }
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

        return metadata.compactMap { plexMetadata in
            guard plexMetadata.type == "track" else { return nil }
            return Track(
                plexID: plexMetadata.ratingKey,
                albumID: albumID,
                title: plexMetadata.title,
                trackNumber: plexMetadata.index ?? 0,
                duration: TimeInterval(plexMetadata.duration ?? 0) / 1000.0,
                artistName: plexMetadata.grandparentTitle ?? plexMetadata.parentTitle ?? "Unknown Artist",
                key: plexMetadata.key ?? "",
                thumbURL: plexMetadata.thumb
            )
        }
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

    // MARK: - PlexAuthAPIProtocol (OAuth Methods)

    /// Request a new PIN for user authorization
    func requestPin() async throws -> PlexPinResponse {
        let url = URL(string: "https://plex.tv/api/v2/pins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addClientHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let pinResponse = try jsonDecoder.decode(PlexPinResponseJSON.self, from: data)
        return PlexPinResponse(id: pinResponse.id, code: pinResponse.code)
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

        let checkResponse = try jsonDecoder.decode(PlexAuthCheckResponseJSON.self, from: data)
        return checkResponse.authToken
    }

    // MARK: - Private Helpers

    /// Build a URLRequest with proper headers and authentication
    private func buildRequest(path: String, requiresAuth: Bool) async throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path

        // Add auth token as query parameter if required
        if requiresAuth {
            let token = try await authManager.validToken()
            components.queryItems = [
                URLQueryItem(name: "X-Plex-Token", value: token)
            ]
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
