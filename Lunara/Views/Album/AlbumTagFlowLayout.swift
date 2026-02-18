import CoreGraphics
import SwiftUI

enum AlbumTagFlowRows {
    static func rowIndices(for sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        guard maxWidth > 0 else {
            return sizes.indices.map { [$0] }
        }

        var rows: [[Int]] = []
        var currentRow: [Int] = []
        var currentWidth: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            let itemWidth = size.width
            let proposedWidth = currentRow.isEmpty ? itemWidth : currentWidth + spacing + itemWidth
            if proposedWidth > maxWidth, !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = [index]
                currentWidth = itemWidth
            } else {
                currentRow.append(index)
                currentWidth = proposedWidth
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}

struct AlbumTagFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    init(spacing: CGFloat = 8, rowSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = AlbumTagFlowRows.rowIndices(for: sizes, maxWidth: maxWidth, spacing: spacing)
        let width = rows.map { row in row.reduce(CGFloat(0)) { $0 + sizes[$1].width } + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
        let height = rows.reduce(CGFloat(0)) { total, row in
            total + (row.map { sizes[$0].height }.max() ?? 0)
        } + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = AlbumTagFlowRows.rowIndices(for: sizes, maxWidth: bounds.width, spacing: spacing)

        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            for index in row {
                let size = sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }
}
