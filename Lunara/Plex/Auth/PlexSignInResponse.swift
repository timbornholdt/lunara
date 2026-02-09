import Foundation

struct PlexSignInResponse: Decodable {
    let user: PlexUser
}

struct PlexUser: Decodable {
    let authToken: String

    enum CodingKeys: String, CodingKey {
        case authToken
        case authenticationToken
        case authentication_token
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let token = try container.decodeIfPresent(String.self, forKey: .authToken) {
            authToken = token
        } else if let token = try container.decodeIfPresent(String.self, forKey: .authenticationToken) {
            authToken = token
        } else if let token = try container.decodeIfPresent(String.self, forKey: .authentication_token) {
            authToken = token
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.authToken,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing auth token")
            )
        }
    }
}
