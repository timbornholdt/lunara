import SwiftUI

/// Static redacted placeholder card mirroring an album-grid cell: a square
/// artwork block over two text stubs. Intentionally motionless — no shimmer or
/// pulse — so it costs nothing while shown and needs no reduce-motion handling
/// (Lunara-uwc).
struct LunaraSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.lunara(.backgroundBase)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                textStub(widthFraction: 0.7)
                textStub(widthFraction: 0.45)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.lunara(.backgroundElevated))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private func textStub(widthFraction: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.lunara(.backgroundBase))
                .frame(width: proxy.size.width * widthFraction)
        }
        .frame(height: 12)
    }
}
