import Foundation

// MARK: - LunaraError Protocol

/// Protocol for all Lunara errors to provide consistent user-facing messages.
/// Each domain defines its own error enum conforming to this protocol.
protocol LunaraError: Error {
    /// Human-readable error message suitable for display in UI
    var userMessage: String { get }
}

// MARK: - LibraryError

/// Errors originating from the Library domain (Plex API, storage, auth, etc.)
enum LibraryError: LunaraError, Equatable {
    /// Plex server is unreachable (network down, wrong URL, server offline)
    case plexUnreachable

    /// Authentication token has expired or is invalid
    case authExpired

    /// Local database is corrupted or unreadable
    case databaseCorrupted

    /// API request failed with specific HTTP error
    case apiError(statusCode: Int, message: String)

    /// Failed to parse response from Plex server
    case invalidResponse

    /// Requested resource not found (album, track, artist, etc.)
    case resourceNotFound(type: String, id: String)

    /// Network request timed out
    case timeout

    /// Generic library operation failed
    case operationFailed(reason: String)

    var userMessage: String {
        switch self {
        case .plexUnreachable:
            return "Cannot reach your Plex server. Check your connection."
        case .authExpired:
            return "Your session has expired. Please sign in again."
        case .databaseCorrupted:
            return "Local library data is corrupted. Try refreshing your library."
        case .apiError(let statusCode, let message):
            return "Plex error (\(statusCode)): \(message)"
        case .invalidResponse:
            return "Received unexpected data from Plex. Try refreshing."
        case .resourceNotFound(let type, _):
            return "\(type.capitalized) not found in your library."
        case .timeout:
            return "Request timed out. Check your connection."
        case .operationFailed(let reason):
            return "Library error: \(reason)"
        }
    }
}

// MARK: - MusicError

/// Errors originating from the Music domain (playback, streaming, audio session, etc.)
enum MusicError: LunaraError, Equatable {
    /// Audio stream failed to load or buffer
    case streamFailed(reason: String)

    /// Requested track is unavailable for playback
    case trackUnavailable

    /// Audio session configuration failed
    case audioSessionFailed

    /// Playback was interrupted and could not resume
    case interruptionFailed

    /// Invalid track URL provided
    case invalidURL

    /// Queue operation failed
    case queueOperationFailed(reason: String)

    /// Playback engine is in an invalid state for the requested operation
    case invalidState(reason: String)

    var userMessage: String {
        switch self {
        case .streamFailed(let reason):
            return "Stream failed: \(reason)"
        case .trackUnavailable:
            return "This track is not available for playback."
        case .audioSessionFailed:
            return "Could not initialize audio. Try restarting the app."
        case .interruptionFailed:
            return "Playback was interrupted and could not resume."
        case .invalidURL:
            return "Invalid audio source. Try refreshing this track."
        case .queueOperationFailed(let reason):
            return "Queue error: \(reason)"
        case .invalidState(let reason):
            return "Playback error: \(reason)"
        }
    }
}
