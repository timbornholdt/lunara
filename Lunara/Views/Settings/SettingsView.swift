import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                lastFMSection
                storageSection
                syncedCollectionsSection
                activeDownloadsSection
                downloadsSection
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await viewModel.completePendingLastFMAuth() }
            }
        }
    }

    // MARK: - Sections

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
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syncedCollectionsSection: some View {
        Section("Synced Collections") {
            if viewModel.syncedCollections.isEmpty {
                Text("No synced collections")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.syncedCollections, id: \.collectionID) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.collection?.title ?? entry.collectionID)
                                .lineLimit(1)
                            Text("\(entry.albumCount) albums")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var activeDownloadsSection: some View {
        let downloads = viewModel.activeDownloads
        if !downloads.isEmpty {
            Section("Downloading") {
                ForEach(downloads, id: \.albumID) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .lineLimit(1)
                        }
                        Spacer()
                        downloadStateLabel(state: entry.state, sizeBytes: 0)
                    }
                }
            }
        }
    }

    private var downloadsSection: some View {
        Section("Downloaded Albums") {
            if viewModel.downloadedAlbums.isEmpty {
                Text("No downloaded albums")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.downloadedAlbums, id: \.albumID) { entry in
                    downloadedAlbumRow(entry)
                        .swipeActions(edge: .trailing) {
                            Button("Remove", role: .destructive) {
                                Task { await viewModel.removeAlbumDownload(albumID: entry.albumID) }
                            }
                        }
                }

                Button("Remove All Downloads", role: .destructive) {
                    Task { await viewModel.removeAllDownloads() }
                }
            }
        }
    }

    private func downloadedAlbumRow(_ entry: (albumID: String, album: Album?, sizeBytes: Int64)) -> some View {
        let state = viewModel.downloadState(forAlbum: entry.albumID)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.album?.title ?? entry.albumID)
                    .lineLimit(1)
                Text(entry.album?.artistName ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            downloadStateLabel(state: state, sizeBytes: entry.sizeBytes)
        }
    }

    @ViewBuilder
    private func downloadStateLabel(state: AlbumDownloadState, sizeBytes: Int64) -> some View {
        switch state {
        case .downloading(let completed, let total):
            HStack(spacing: 6) {
                ProgressView(value: Double(completed), total: Double(total))
                    .frame(width: 60)
                Text("\(completed)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        default:
            Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lastFMSection: some View {
        Section("Last.fm") {
            if viewModel.isLastFMAuthenticated {
                HStack {
                    Text("Connected")
                    Spacer()
                    Text(viewModel.lastFMUsername ?? "")
                        .foregroundStyle(.secondary)
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
}
