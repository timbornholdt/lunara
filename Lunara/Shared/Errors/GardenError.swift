import Foundation

/// Errors originating from the Garden domain (todo submissions to timbornholdt.com)
enum GardenError: LunaraError, Equatable, Sendable {
    /// API key is missing or invalid
    case unauthorized

    /// Server rejected the request due to validation errors
    case validationFailed

    /// Network request failed
    case networkError

    /// Unexpected server error
    case serverError

    var userMessage: String {
        switch self {
        case .unauthorized:
            return "Garden API key is invalid. Check your configuration."
        case .validationFailed:
            return "Could not submit todo. Make sure the body is not empty."
        case .networkError:
            return "Could not reach the garden. Check your connection."
        case .serverError:
            return "Something went wrong on the garden server. Try again later."
        }
    }
}
