import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

        NavigationStack {
            ZStack {
                LinenBackgroundView(palette: palette)
                Form {
                    Section("Downloads") {
                        NavigationLink {
                            ManageDownloadsView(
                                playbackViewModel: playbackViewModel,
                                signOut: signOut
                            )
                        } label: {
                            Label("Manage Downloads", systemImage: "arrow.down.circle")
                        }
                    }

                    Section("Diagnostics") {
                        ForEach(viewModel.diagnosticToggles) { toggle in
                            Toggle(
                                toggle.title,
                                isOn: Binding(
                                    get: { viewModel.isEnabled(toggle.id) },
                                    set: { viewModel.setToggle(toggle.id, enabled: $0) }
                                )
                            )
                        }
                        if FileManager.default.fileExists(atPath: DiagnosticsLogger.shared.fileURL.path) {
                            ShareLink(
                                item: DiagnosticsLogger.shared.fileURL
                            ) {
                                Label("Share Diagnostics Log", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Label("Share Diagnostics Log", systemImage: "square.and.arrow.up")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Experiments") {
                        if viewModel.showsEmptyExperimentsState {
                            Text("No experiments available yet.")
                                .foregroundStyle(palette.textSecondary)
                        } else {
                            ForEach(viewModel.experimentToggles) { toggle in
                                Toggle(
                                    toggle.title,
                                    isOn: Binding(
                                        get: { viewModel.isEnabled(toggle.id) },
                                        set: { viewModel.setToggle(toggle.id, enabled: $0) }
                                    )
                                )
                            }
                        }
                    }

                    Section {
                        Button("Sign Out", role: .destructive) {
                            viewModel.requestSignOut()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                viewModel.signOutConfirmationTitle,
                isPresented: Binding(
                    get: { viewModel.isSignOutConfirmationPresented },
                    set: { isPresented in
                        if isPresented == false {
                            viewModel.cancelSignOut()
                        }
                    }
                )
            ) {
                Button("Cancel", role: .cancel) {
                    viewModel.cancelSignOut()
                }
                Button(viewModel.signOutConfirmationButtonTitle, role: .destructive) {
                    dismiss()
                    viewModel.confirmSignOut()
                }
            } message: {
                Text(viewModel.signOutConfirmationMessage)
            }
        }
    }
}
