import SwiftUI

struct SignInView: View {

    let coordinator: AppCoordinator

    @State private var pinCode: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var authState: AuthState = .initial

    enum AuthState {
        case initial
        case showingPin(String)
        case waitingForAuth
        case error(String)
    }

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App Title
            VStack(spacing: 8) {
                Text("Lunara")
                    .font(.system(size: 48, weight: .light, design: .serif))
                Text("Sign in with Plex")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Auth Flow Content
            Group {
                switch authState {
                case .initial:
                    initialView
                case .showingPin(let code):
                    pinView(code: code)
                case .waitingForAuth:
                    waitingView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .frame(maxWidth: 400)

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - View States

    private var initialView: some View {
        VStack(spacing: 20) {
            Button(action: startSignIn) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("Sign In with Plex")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)

            // Debug quick sign-in hint
            if hasLocalConfig {
                Text("LocalConfig.plist detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pinView(code: String) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text("Enter this code at:")
                    .font(.headline)

                Link("plex.tv/link", destination: URL(string: "https://plex.tv/link")!)
                    .font(.title3)

                // Pin Code Display
                Text(code)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .tracking(8)
                    .foregroundStyle(.primary)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
            }

            Text("Waiting for authorization...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView()
                .progressViewStyle(.circular)
        }
    }

    private var waitingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Authorizing...")
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                authState = .initial
                errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func startSignIn() {
        isLoading = true
        authState = .waitingForAuth

        Task {
            do {
                // Request pin from Plex
                let pinResponse = try await coordinator.plexClient.requestPin()

                await MainActor.run {
                    authState = .showingPin(pinResponse.code)
                    isLoading = false
                }

                // Poll for authorization
                await pollForAuthorization(pinID: pinResponse.id)

            } catch {
                await MainActor.run {
                    authState = .error(error.localizedDescription)
                    isLoading = false
                }
            }
        }
    }

    private func pollForAuthorization(pinID: Int) async {
        // Poll for up to 5 minutes (150 attempts, 2 seconds apart)
        for _ in 0..<150 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            do {
                if let token = try await coordinator.plexClient.checkPin(pinID: pinID) {
                    // Got token! Save it
                    try coordinator.authManager.setToken(token)
                    return // Success, view will update automatically
                }
            } catch {
                // Network error or other issue - continue trying
                continue
            }
        }

        // Timeout
        await MainActor.run {
            authState = .error("Authorization timed out. Please try again.")
        }
    }


    private var hasLocalConfig: Bool {
        Bundle.main.path(forResource: "LocalConfig", ofType: "plist") != nil
    }
}

// MARK: - Preview

#Preview {
    SignInView(coordinator: AppCoordinator())
}
