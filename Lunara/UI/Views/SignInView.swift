import SwiftUI
import UIKit

struct SignInView: View {
    @StateObject var viewModel: AuthViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    enum Layout {
        static let globalPadding = LunaraTheme.Layout.globalPadding
        static let primaryButtonHeight = LunaraTheme.Layout.primaryButtonHeight
        static let cardCornerRadius = LunaraTheme.Layout.cardCornerRadius
        static let cardHorizontalPadding = LunaraTheme.Layout.cardHorizontalPadding
        static let sectionSpacing: CGFloat = 24
        static let blockSpacing: CGFloat = 12
        static let titleSpacing: CGFloat = 8
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

        ZStack {
            LinenBackgroundView(palette: palette)
            VStack(spacing: Layout.sectionSpacing) {
                VStack(spacing: Layout.titleSpacing) {
                    Text("Lunara")
                        .font(LunaraTheme.Typography.display(size: 34))
                        .foregroundStyle(palette.textPrimary)
                    Text("Sign in to your Plex server")
                        .font(.system(size: 17))
                        .foregroundStyle(palette.textSecondary)
                }

                VStack(spacing: Layout.blockSpacing) {
                    TextField("Plex Server URL (https://...:32400)", text: $viewModel.serverURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 17))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, Layout.cardHorizontalPadding)
                        .frame(height: Layout.primaryButtonHeight)
                        .background(palette.raised)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .stroke(palette.borderSubtle, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                }

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.stateError)
                }

                Button {
                    Task { await viewModel.signIn() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In with Plex")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(LunaraPrimaryButtonStyle(palette: palette))
                .disabled(viewModel.isLoading)

                if let authURL = viewModel.authURL {
                    VStack(spacing: Layout.titleSpacing) {
                        Text("If Safari doesn't open, copy this link:")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.textSecondary)
                        Text(authURL.absoluteString)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Button("Copy Auth Link") {
                            UIPasteboard.general.string = authURL.absoluteString
                        }
                        .buttonStyle(LunaraSecondaryButtonStyle(palette: palette))
                    }
                }

#if DEBUG
                Group {
                    if LocalPlexConfig.credentials != nil {
                        Button("Quick Sign-In (Debug)") {
                            Task { await viewModel.signInWithLocalConfig() }
                        }
                        .buttonStyle(LunaraSecondaryButtonStyle(palette: palette))
                        .disabled(viewModel.isLoading)
                    }

                    if !viewModel.debugLog.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(viewModel.debugLog, id: \.self) { line in
                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                        .padding(.horizontal, Layout.cardHorizontalPadding)
                        .padding(.vertical, 8)
                        .background(palette.raised)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .stroke(palette.borderSubtle, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                    }
                }
#endif

            Spacer()
        }
        .padding(Layout.globalPadding)
        .task {
#if DEBUG
            while !viewModel.didFinishInitialTokenCheck {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard viewModel.isAuthenticated == false else { return }
            if LocalPlexConfig.credentials?.autoStartAuth == true {
                await viewModel.signInWithLocalConfig()
            } else {
                viewModel.applyLocalConfigIfAvailable()
            }
#endif
        }
        .onChange(of: viewModel.authURL) { _, url in
            guard let url else { return }
            openURL(url)
            viewModel.authURL = nil
        }
    }
}
}
