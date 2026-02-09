import Foundation

#if DEBUG
enum LocalPlexConfig {
    struct Credentials: Decodable {
        let serverURL: String
        let username: String
        let password: String

        enum CodingKeys: String, CodingKey {
            case serverURL = "PLEX_SERVER_URL"
            case username = "PLEX_USERNAME"
            case password = "PLEX_PASSWORD"
        }
    }

    static let credentials: Credentials? = load()

    private static func load() -> Credentials? {
        guard let url = Bundle.main.url(forResource: "LocalConfig", withExtension: "plist") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListDecoder().decode(Credentials.self, from: data)
    }
}
#endif
