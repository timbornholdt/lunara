import Foundation

struct PlexResponse<Item: Decodable>: Decodable {
    let mediaContainer: PlexMediaContainer<Item>

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    static func decode(from json: String) throws -> PlexResponse<Item> {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(PlexResponse<Item>.self, from: data)
    }
}

struct PlexMediaContainer<Item: Decodable>: Decodable {
    let size: Int
    let totalSize: Int?
    let offset: Int?
    let items: [Item]

    enum CodingKeys: String, CodingKey {
        case size
        case totalSize
        case offset
        case items = "Metadata"
    }
}
