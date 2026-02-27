import SwiftUI

private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    let foregroundStyle: Color
    var speed: Double = 30 // points per second

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?

    private var scrollDistance: CGFloat { max(0, textWidth - containerWidth) }
    private var canScroll: Bool { scrollDistance > 4 }

    var body: some View {
        // Invisible truncating text for layout height only
        Text(text)
            .font(font)
            .lineLimit(1)
            .foregroundStyle(.clear)
            .overlay {
                GeometryReader { geo in
                    // Visible scrolling text
                    Text(text)
                        .font(font)
                        .foregroundStyle(foregroundStyle)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: offset)

                    // Hidden measurement text (same fixedSize text, measures its width)
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .fixedSize()
                        .hidden()
                        .background(
                            GeometryReader { textGeo in
                                Color.clear.preference(
                                    key: TextWidthKey.self,
                                    value: textGeo.size.width
                                )
                            }
                        )
                }
                .clipped()
                .onPreferenceChange(TextWidthKey.self) { width in
                    textWidth = width
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                containerWidth = newWidth
            }
            .onChange(of: text) {
                animationTask?.cancel()
                animationTask = nil
                withAnimation(nil) { offset = 0 }
            }
            .onChange(of: canScroll) {
                if canScroll {
                    startScrollCycle()
                } else {
                    animationTask?.cancel()
                    animationTask = nil
                    withAnimation(nil) { offset = 0 }
                }
            }
            .onAppear {
                if canScroll {
                    startScrollCycle()
                }
            }
    }

    private func startScrollCycle() {
        animationTask?.cancel()
        withAnimation(nil) { offset = 0 }

        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                // Pause at start
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, canScroll else { return }

                // Scroll to end
                let dist = scrollDistance
                let forwardDuration = dist / speed
                withAnimation(.linear(duration: forwardDuration)) {
                    offset = -dist
                }
                try? await Task.sleep(for: .seconds(forwardDuration))
                guard !Task.isCancelled else { return }

                // Pause at end
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }

                // Scroll back to start
                let returnDuration = dist / speed
                withAnimation(.linear(duration: returnDuration)) {
                    offset = 0
                }
                try? await Task.sleep(for: .seconds(returnDuration))
                guard !Task.isCancelled else { return }
            }
        }
    }
}
