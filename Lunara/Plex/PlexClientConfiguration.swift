import Foundation

struct PlexClientConfiguration: Sendable {
    let clientIdentifier: String
    let product: String
    let version: String
    let platform: String

    var defaultHeaders: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": product,
            "X-Plex-Version": version,
            "X-Plex-Platform": platform,
            "Accept": "application/json"
        ]
    }
}
