import SwiftUI

struct NowPlayingBarView: View {
    let state: NowPlayingState
    let palette: LunaraTheme.PaletteColors
    let onTogglePlayPause: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onTogglePlayPause) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accentPrimary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.trackTitle)
                        .font(LunaraTheme.Typography.displayBold(size: 15))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    Text(timeText)
                        .font(LunaraTheme.Typography.displayRegular(size: 12).monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: 8)
            }

            if let duration = state.duration, duration > 0 {
                ProgressView(value: min(state.elapsedTime, duration), total: duration)
                    .tint(palette.accentPrimary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(palette.raised)
        .overlay(
            RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius))
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 8,
            x: 0,
            y: 1
        )
    }

    private var timeText: String {
        let elapsed = formatTime(state.elapsedTime)
        if let duration = state.duration {
            return "\(elapsed) / \(formatTime(duration))"
        }
        return elapsed
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let minutes = totalSeconds / 60
        let remaining = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

struct PlaybackErrorBanner: View {
    let message: String
    let palette: LunaraTheme.PaletteColors
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.stateError)

                Text(message)
                    .font(LunaraTheme.Typography.displayRegular(size: 13))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(palette.raised)
            .overlay(
                RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius))
        }
        .buttonStyle(.plain)
    }
}
