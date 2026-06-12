import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var copiedPlexCredentials = false
    @Environment(ColorSchemeManager.self) private var colorSchemeManager

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {

                playbackSection
                lastFMSection
                storageSection
                syncedCollectionsSection
                downloadsLinkSection
                diagnosticsSection
                accountSection
            }
            .navigationTitle("Settings")
            .lunaraLinenBackground()
            .task {
                await viewModel.load()
            }
            .task {
                await viewModel.observeDownloadProgress()
            }
            // Tab views stay alive across tab switches, so .task alone leaves
            // this screen stale when sync state changes elsewhere (Lunara-5xu).
            .onAppear {
                Task { await viewModel.load() }
            }
            .onChange(of: viewModel.downloadManager.syncStateVersion) {
                Task { await viewModel.load() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await viewModel.completePendingLastFMAuth() }
            }
        }
    }

    // MARK: - Sections

    private var playbackSection: some View {
        Section("Playback") {
            Toggle(
                "Loudness Leveling",
                isOn: Binding(
                    get: { viewModel.isLoudnessLevelingEnabled },
                    set: { viewModel.isLoudnessLevelingEnabled = $0 }
                )
            )
            Toggle(
                "Crossfade",
                isOn: Binding(
                    get: { viewModel.isCrossfadeEnabled },
                    set: { viewModel.isCrossfadeEnabled = $0 }
                )
            )
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            ForEach(LunaraColorPreset.allCases, id: \.self) { preset in
                Button {
                    colorSchemeManager.preset = preset
                } label: {
                    HStack(spacing: 12) {
                        colorSwatch(for: preset)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.displayName)
                                .foregroundStyle(Color.lunara(.textPrimary))
                            Text(preset.description)
                                .font(.caption)
                                .foregroundStyle(Color.lunara(.textSecondary))
                        }
                        Spacer()
                        if preset == colorSchemeManager.preset {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.lunara(.accentPrimary))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }

    private func colorSwatch(for preset: LunaraColorPreset) -> some View {
        let bg = LunaraVisualTokens.lightColorToken(for: .backgroundBase, preset: preset)
        let accent = LunaraVisualTokens.lightColorToken(for: .accentPrimary, preset: preset)
        let text = LunaraVisualTokens.lightColorToken(for: .textPrimary, preset: preset)

        return HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: bg.red, green: bg.green, blue: bg.blue))
                .frame(width: 10, height: 28)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: accent.red, green: accent.green, blue: accent.blue))
                .frame(width: 10, height: 28)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: text.red, green: text.green, blue: text.blue))
                .frame(width: 10, height: 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }


    private var storageSection: some View {
        Section("Offline Storage") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Storage Limit: \(viewModel.formattedLimit)")
                Slider(
                    value: Binding(
                        get: { viewModel.settings.storageLimitGB },
                        set: { viewModel.updateStorageLimit($0) }
                    ),
                    in: 1...50,
                    step: 1
                )
            }

            Toggle(
                "Wi-Fi Only",
                isOn: Binding(
                    get: { viewModel.settings.wifiOnly },
                    set: { viewModel.updateWifiOnly($0) }
                )
            )

            HStack {
                Text("Used")
                Spacer()
                Text("\(viewModel.formattedUsage) of \(viewModel.formattedLimit)")
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
    }

    private var syncedCollectionsSection: some View {
        Section("Synced Collections") {
            if viewModel.syncedCollections.isEmpty {
                Text("No synced collections")
                    .foregroundStyle(Color.lunara(.textSecondary))
            } else {
                ForEach(viewModel.syncedCollections, id: \.collectionID) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.collection?.title ?? entry.collectionID)
                                .lineLimit(1)
                            Text("\(entry.albumCount) albums")
                                .font(.caption)
                                .foregroundStyle(Color.lunara(.textSecondary))
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Unsync", role: .destructive) {
                            Task { await viewModel.unsyncCollection(collectionID: entry.collectionID) }
                        }
                    }
                }
            }
        }
    }

    /// One summary row that opens the dedicated downloads manager (Lunara-j0l).
    private var downloadsLinkSection: some View {
        Section("Downloads") {
            NavigationLink {
                DownloadsView(viewModel: viewModel)
            } label: {
                HStack {
                    Text("Manage Downloads")
                    Spacer()
                    Text(downloadsSummary)
                        .font(.caption)
                        .foregroundStyle(Color.lunara(.textSecondary))
                }
            }
        }
    }

    private var downloadsSummary: String {
        let count = viewModel.downloadedAlbums.count
        let albums = count == 1 ? "1 album" : "\(count) albums"
        return "\(albums) · \(viewModel.formattedUsage)"
    }

    private var lastFMSection: some View {
        Section("Last.fm") {
            if viewModel.isLastFMAuthenticated {
                HStack {
                    Text("Connected")
                    Spacer()
                    Text(viewModel.lastFMUsername ?? "")
                        .foregroundStyle(Color.lunara(.textSecondary))
                }

                Toggle(
                    "Scrobbling",
                    isOn: Binding(
                        get: { viewModel.isScrobblingEnabled },
                        set: { viewModel.isScrobblingEnabled = $0 }
                    )
                )

                Button("Sign Out of Last.fm", role: .destructive) {
                    viewModel.signOutOfLastFM()
                }
            } else {
                Button("Sign In to Last.fm") {
                    print("[LastFM] Button tapped")
                    Task {
                        print("[LastFM] Task started, authManager: \(String(describing: viewModel.lastFMAuthManager))")
                        await viewModel.signInToLastFM()
                        print("[LastFM] signInToLastFM returned")
                    }
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
            }
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Toggle(
                "Record playback diagnostics",
                isOn: Binding(
                    get: { viewModel.isDiagnosticsRecordingEnabled },
                    set: { viewModel.isDiagnosticsRecordingEnabled = $0 }
                )
            )

            if let logURL = viewModel.diagnosticsLogURL {
                ShareLink("Share Playback Log", item: logURL)
                Button("Clear Log", role: .destructive) {
                    viewModel.clearDiagnosticsLog()
                }
            }

            if viewModel.canCopyPlexCredentials {
                Button {
                    Task {
                        guard let credentials = await viewModel.plexCredentials() else { return }
                        UIPasteboard.general.string = credentials
                        copiedPlexCredentials = true
                        try? await Task.sleep(for: .seconds(2))
                        copiedPlexCredentials = false
                    }
                } label: {
                    HStack {
                        Text("Copy Plex Server + Token")
                        Spacer()
                        if copiedPlexCredentials {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.lunara(.accentPrimary))
                        }
                    }
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Records memory and playback events to an on-device log you can share. Includes track identifiers; stays on your device until you share or clear it. Copy Plex Server + Token puts your server address and auth token on the clipboard — treat it like a password.")
        }
    }
}
