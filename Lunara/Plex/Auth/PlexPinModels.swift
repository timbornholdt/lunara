import Foundation

struct PlexPin: Decodable, Equatable, Sendable {
    let id: Int
    let code: String
}

struct PlexPinStatus: Decodable, Equatable, Sendable {
    let id: Int
    let code: String
    let authToken: String?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case authToken
        case authTokenSnake = "auth_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        if let token = try container.decodeIfPresent(String.self, forKey: .authToken) {
            authToken = token
        } else {
            authToken = try container.decodeIfPresent(String.self, forKey: .authTokenSnake)
        }
    }

    init(id: Int, code: String, authToken: String?) {
        self.id = id
        self.code = code
        self.authToken = authToken
    }
}
