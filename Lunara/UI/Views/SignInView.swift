import SwiftUI
import UIKit

struct SignInView: View {
    @StateObject var viewModel: AuthViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Lunara")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text("Sign in to your Plex server")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Plex Server URL (https://...:32400)", text: $viewModel.serverURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            if let status = viewModel.statusMessage {
                Text(status)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await viewModel.signIn() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In with Plex")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)

            if let authURL = viewModel.authURL {
                VStack(spacing: 8) {
                    Text("If Safari doesn't open, copy this link:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(authURL.absoluteString)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button("Copy Auth Link") {
                        UIPasteboard.general.string = authURL.absoluteString
                    }
                    .buttonStyle(.bordered)
                }
            }

#if DEBUG
            if LocalPlexConfig.credentials != nil {
                Button("Quick Sign-In (Debug)") {
                    Task { await viewModel.signInWithLocalConfig() }
                }
                .buttonStyle(.bordered)
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
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
#endif

            Spacer()
        }
        .padding(24)
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
