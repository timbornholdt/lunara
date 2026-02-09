import Foundation
import Testing
@testable import Lunara

struct PlexPaginatorTests {
    @Test func fetchesAllPagesUntilTotalSizeReached() async throws {
        let paginator = PlexPaginator(pageSize: 2)
        let pages: [PlexPage<Int>] = [
            PlexPage(items: [1, 2], offset: 0, size: 2, totalSize: 5),
            PlexPage(items: [3, 4], offset: 2, size: 2, totalSize: 5),
            PlexPage(items: [5], offset: 4, size: 1, totalSize: 5)
        ]
        var index = 0

        let results = try await paginator.fetchAll { _ in
            defer { index += 1 }
            return pages[index]
        }

        #expect(results == [1, 2, 3, 4, 5])
    }

    @Test func stopsIfPageReturnsEmptyItems() async throws {
        let paginator = PlexPaginator(pageSize: 50)
        let pages: [PlexPage<Int>] = [
            PlexPage(items: [1], offset: 0, size: 1, totalSize: 10),
            PlexPage(items: [], offset: 1, size: 0, totalSize: 10)
        ]
        var index = 0

        let results = try await paginator.fetchAll { _ in
            defer { index += 1 }
            return pages[index]
        }

        #expect(results == [1])
    }
}
