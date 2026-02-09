import Foundation

struct PlexPage<Item> {
    let items: [Item]
    let offset: Int
    let size: Int
    let totalSize: Int
}
