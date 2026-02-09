import Foundation

struct PlexLibrarySection: Decodable, Equatable, Sendable {
    let key: String
    let title: String
    let type: String
}

struct PlexDirectoryResponse<Item: Decodable>: Decodable {
    let mediaContainer: PlexDirectoryContainer<Item>

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexDirectoryContainer<Item: Decodable>: Decodable {
    let size: Int
    let items: [Item]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Directory"
    }
}
