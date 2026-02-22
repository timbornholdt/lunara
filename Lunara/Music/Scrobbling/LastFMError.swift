import Foundation

/// Errors originating from Last.fm scrobbling operations.
enum LastFMError: LunaraError, Equatable {
    /// Not authenticated with Last.fm
    case notAuthenticated

    /// Last.fm API returned an error
    case apiError(code: Int, message: String)

    /// Failed to build a valid API request
    case invalidRequest

    /// Network request failed
    case networkError(String)

    /// Failed to parse Last.fm response
    case invalidResponse

    /// Auth callback missing required token
    case missingCallbackToken

    var userMessage: String {
        switch self {
        case .notAuthenticated:
            return "Not signed in to Last.fm."
        case .apiError(_, let message):
            return "Last.fm error: \(message)"
        case .invalidRequest:
            return "Failed to build Last.fm request."
        case .networkError(let reason):
            return "Last.fm network error: \(reason)"
        case .invalidResponse:
            return "Unexpected response from Last.fm."
        case .missingCallbackToken:
            return "Last.fm authorization failed. Please try again."
        }
    }
}
