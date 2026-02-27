import Observation
import SwiftUI

struct LunaraErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lunara(.bannerText))

                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.lunara(.bannerText))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.lunara(.bannerText).opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.lunara(.bannerBackground))
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Error")
        .accessibilityValue(message)
        .accessibilityHint("Dismisses error banner")
    }
}

private struct LunaraErrorBannerModifier: ViewModifier {
    @Bindable var bannerState: ErrorBannerState

    init(bannerState: ErrorBannerState) {
        self._bannerState = Bindable(bannerState)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = bannerState.message {
                    LunaraErrorBanner(message: message) {
                        bannerState.dismiss()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.88), value: bannerState.message)
    }
}

extension View {
    func lunaraErrorBanner(using bannerState: ErrorBannerState) -> some View {
        modifier(LunaraErrorBannerModifier(bannerState: bannerState))
    }
}
