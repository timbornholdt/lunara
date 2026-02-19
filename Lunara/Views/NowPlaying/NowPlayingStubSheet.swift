import SwiftUI

/// Placeholder full-screen sheet. Will be replaced by the real NowPlayingScreen next session.
struct NowPlayingStubSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.lunara(.backgroundBase)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.lunara(.borderSubtle))
                    .frame(width: 36, height: 5)

                Spacer()

                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.lunara(.textSecondary))

                Text("Now Playing")
                    .font(Font.custom("PlayfairDisplay-Regular", size: 28))
                    .foregroundStyle(Color.lunara(.textPrimary))

                Text("Full screen coming next session.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.lunara(.textSecondary))

                Spacer()
            }
            .padding(.top, 12)
            .padding(.horizontal, 32)
        }
    }
}

#Preview {
    NowPlayingStubSheet()
}
