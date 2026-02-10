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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        totalSize = try container.decodeIfPresent(Int.self, forKey: .totalSize)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
}
