import CoreFoundation
import CoreGraphics
import Testing
@testable import Lunara

struct AlbumTagFlowLayoutTests {
    @Test
    func rowIndices_wrapsToNextLineWhenWidthExceeded() {
        let sizes = [
            CGSize(width: 90, height: 32),
            CGSize(width: 80, height: 32),
            CGSize(width: 70, height: 32),
            CGSize(width: 60, height: 32)
        ]

        let rows = AlbumTagFlowRows.rowIndices(for: sizes, maxWidth: 200, spacing: 10)

        #expect(rows.count == 2)
        #expect(rows[0] == [0, 1])
        #expect(rows[1] == [2, 3])
    }

    @Test
    func rowIndices_keepsSingleItemPerRowWhenItemTooWide() {
        let sizes = [
            CGSize(width: 240, height: 32),
            CGSize(width: 80, height: 32)
        ]

        let rows = AlbumTagFlowRows.rowIndices(for: sizes, maxWidth: 200, spacing: 10)

        #expect(rows.count == 2)
        #expect(rows[0] == [0])
        #expect(rows[1] == [1])
    }

    @Test
    func rowIndices_usesNaturalSingleRowWhenSpaceAllows() {
        let sizes = [
            CGSize(width: 50, height: 30),
            CGSize(width: 60, height: 30),
            CGSize(width: 70, height: 30)
        ]

        let rows = AlbumTagFlowRows.rowIndices(for: sizes, maxWidth: 400, spacing: 8)

        #expect(rows.count == 1)
        #expect(rows[0] == [0, 1, 2])
    }
}
