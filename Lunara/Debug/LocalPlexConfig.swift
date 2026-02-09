import Foundation

#if DEBUG
enum LocalPlexConfig {
    struct Credentials: Decodable {
        let serverURL: String
        let autoStartAuth: Bool?

        enum CodingKeys: String, CodingKey {
            case serverURL = "PLEX_SERVER_URL"
            case autoStartAuth = "AUTO_START_AUTH"
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
