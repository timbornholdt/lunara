import Foundation

struct PlexPaginator {
    let pageSize: Int

    func fetchAll<Item>(
        fetchPage: @escaping (Int) async throws -> PlexPage<Item>
    ) async throws -> [Item] {
        var allItems: [Item] = []
        var offset = 0
        var total = Int.max

        while offset < total {
            let page = try await fetchPage(offset)
            if page.items.isEmpty {
                break
            }
            allItems.append(contentsOf: page.items)
            total = page.totalSize
            offset = page.offset + page.items.count
        }

        return allItems
    }
}
