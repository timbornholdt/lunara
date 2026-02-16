import Foundation

// MARK: - Plex Auth Models

/// Response from Plex pin request endpoint
struct PlexPinResponse: Codable {
    let id: Int
    let code: String
}

/// Response from Plex auth token exchange
struct PlexAuthTokenResponse: Codable {
    let authToken: String?
}

// MARK: - PlexAuthAPIProtocol

/// Protocol for Plex authentication API endpoints
/// Allows mocking in tests without full PlexAPIClient dependency
protocol PlexAuthAPIProtocol {
    /// Request a new PIN for user authorization
    /// - Returns: Pin ID and 4-character code to display to user
    func requestPin() async throws -> PlexPinResponse

    /// Check if user has authorized the PIN
    /// - Parameter pinID: The pin ID from requestPin()
    /// - Returns: Auth token if authorized, nil if still waiting
    func checkPin(pinID: Int) async throws -> String?
}
