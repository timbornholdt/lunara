import Foundation
import UIKit

enum PlexDefaults {
    static let authBaseURL = URL(string: "https://plex.tv")!
    static let maxArtworkSize = 2048

    static func configuration() -> PlexClientConfiguration {
        PlexClientConfiguration(
            clientIdentifier: clientIdentifier(),
            product: "Lunara",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1",
            platform: UIDevice.current.systemName
        )
    }

    private static func clientIdentifier() -> String {
        let key = "plex.client.identifier"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newValue = UUID().uuidString
        UserDefaults.standard.set(newValue, forKey: key)
        return newValue
    }
}
