import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    let progress: Double // 0.0 to 1.0
    let filledColor: Color
    let unfilledColor: Color

    var body: some View {
        GeometryReader { geo in
            let barCount = levels.count
            guard barCount > 0 else { return AnyView(EmptyView()) }
            let barWidth = max(1, (geo.size.width - CGFloat(barCount - 1)) / CGFloat(barCount))
            let spacing: CGFloat = 1
            let progressX = geo.size.width * progress

            return AnyView(
                HStack(spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let level = CGFloat(levels[i])
                        let barHeight = max(2, level * geo.size.height)
                        let barX = CGFloat(i) * (barWidth + spacing) + barWidth / 2

                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(barX <= progressX ? filledColor : unfilledColor)
                            .frame(width: barWidth, height: barHeight)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            )
        }
    }
}
