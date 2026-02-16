import Foundation

/// Represents the current state of the playback engine.
/// This is a shared type used by both Music domain and UI layer.
enum PlaybackState: Equatable, Sendable {
    /// No track is loaded or ready to play
    case idle

    /// A track is loading (streaming URL buffering, AVPlayerItem preparing)
    /// UI should show loading indicators to distinguish from paused state
    case buffering

    /// A track is actively playing
    case playing

    /// Playback is paused (track is loaded and ready to resume)
    case paused

    /// Playback encountered an error
    /// Associated string contains a user-facing error message
    case error(String)

    // MARK: - Computed Properties

    /// Whether audio is currently playing
    var isPlaying: Bool {
        self == .playing
    }

    /// Whether the player is in a loading state
    var isBuffering: Bool {
        self == .buffering
    }

    /// Whether playback can be resumed
    var canResume: Bool {
        self == .paused
    }

    /// Whether the player is in an error state
    var hasError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    /// Error message if in error state, nil otherwise
    var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}
