import SwiftUI

struct AlphabetIndexOverlay: View {
    let letters: [String]
    let palette: LunaraTheme.PaletteColors
    let onSelect: (String) -> Void

    @State private var lastSelection: String?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 2) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(LunaraTheme.Typography.displayRegular(size: 11))
                        .foregroundStyle(isDragging ? palette.accentPrimary : palette.textSecondary)
                        .frame(width: 18, height: 12)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(palette.raised.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let index = indexFor(location: value.location, height: proxy.size.height)
                        guard letters.indices.contains(index) else { return }
                        let selection = letters[index]
                        if selection != lastSelection {
                            lastSelection = selection
                            onSelect(selection)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastSelection = nil
                    }
            )
        }
        .frame(width: 32)
    }

    private func indexFor(location: CGPoint, height: CGFloat) -> Int {
        guard height > 0 else { return 0 }
        let clampedY = min(max(location.y, 0), height - 1)
        let ratio = clampedY / height
        let rawIndex = Int((ratio * CGFloat(letters.count)).rounded(.down))
        return min(max(rawIndex, 0), max(letters.count - 1, 0))
    }
}
