import SwiftUI

struct SignInView: View {
    @StateObject var viewModel: AuthViewModel

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
                TextField("Email", text: $viewModel.login)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)

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
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)

            Spacer()
        }
        .padding(24)
    }
}
