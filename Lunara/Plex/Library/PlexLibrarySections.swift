import Foundation

struct PlexLibrarySection: Codable, Equatable, Sendable {
    let key: String
    let title: String
    let type: String
}

struct PlexDirectoryResponse<Item: Decodable & Encodable>: Codable {
    let mediaContainer: PlexDirectoryContainer<Item>

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexDirectoryContainer<Item: Decodable & Encodable>: Codable {
    let size: Int
    let items: [Item]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Directory"
    }
}
