import SwiftUI

struct FlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    init(spacing: CGFloat, rowSpacing: CGFloat) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        let result = layout(subviews: subviews, maxWidth: maxWidth)
        return CGSize(width: maxWidth, height: result.totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, maxWidth: bounds.width)
        for placement in result.placements {
            placement.subview.place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> LayoutResult {
        var placements: [Placement] = []
        var rowX: CGFloat = 0
        var rowY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowX + size.width > maxWidth, rowX > 0 {
                rowY += rowHeight + rowSpacing
                rowX = 0
                rowHeight = 0
            }

            placements.append(Placement(subview: subview, origin: CGPoint(x: rowX, y: rowY), size: size))
            rowX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let totalHeight = rowY + rowHeight
        return LayoutResult(placements: placements, totalHeight: totalHeight)
    }

    private struct LayoutResult {
        let placements: [Placement]
        let totalHeight: CGFloat
    }

    private struct Placement {
        let subview: Subviews.Element
        let origin: CGPoint
        let size: CGSize
    }
}
