import SwiftUI

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

#if DEBUG
            if LocalPlexConfig.credentials != nil {
                Button("Quick Sign-In (Debug)") {
                    Task { await viewModel.signInWithLocalConfig() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
            }
#endif

            Spacer()
        }
        .padding(24)
        .task {
#if DEBUG
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
