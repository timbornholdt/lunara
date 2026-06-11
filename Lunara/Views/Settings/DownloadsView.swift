import SwiftUI

/// Dedicated downloads manager pushed from Settings (Lunara-j0l): every row
/// carries the album's thumbnail and taps through to the album page.
struct DownloadsView: View {
    let viewModel: SettingsViewModel
    @State private var selectedAlbum: Album?

    var body: some View {
        List {
            activeSection
            downloadedSection
        }
        .navigationTitle("Downloads")
        .lunaraLinenBackground()
        .navigationDestination(item: $selectedAlbum) { album in
            if let albumViewModel = viewModel.makeAlbumDetailViewModel(for: album) {
                AlbumDetailView(viewModel: albumViewModel)
            }
        }
        .task {
            await viewModel.load()
        }
        .task {
            await viewModel.observeDownloadProgress()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var activeSection: some View {
        let downloads = viewModel.activeDownloads
        if !downloads.isEmpty {
            Section("Downloading") {
                ForEach(downloads, id: \.albumID) { entry in
                    albumRow(
                        albumID: entry.albumID,
                        album: album(for: entry.albumID),
                        fallbackTitle: entry.name
                    ) {
                        downloadStateLabel(state: entry.state, sizeBytes: 0)
                    }
                }
            }
        }
    }

    private var downloadedSection: some View {
        Section("Downloaded Albums") {
            if viewModel.downloadedAlbums.isEmpty {
                Text("No downloaded albums")
                    .foregroundStyle(Color.lunara(.textSecondary))
            } else {
                ForEach(viewModel.downloadedAlbums, id: \.albumID) { entry in
                    albumRow(
                        albumID: entry.albumID,
                        album: entry.album,
                        fallbackTitle: entry.albumID
                    ) {
                        downloadStateLabel(
                            state: viewModel.downloadState(forAlbum: entry.albumID),
                            sizeBytes: entry.sizeBytes
                        )
                    }
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

    // MARK: - Rows

    private func album(for albumID: String) -> Album? {
        viewModel.downloadedAlbums.first { $0.albumID == albumID }?.album
            ?? viewModel.album(forActiveDownload: albumID)
    }

    private func albumRow(
        albumID: String,
        album: Album?,
        fallbackTitle: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            rowThumbnail(albumID: albumID)

            VStack(alignment: .leading, spacing: 2) {
                Text(album?.title ?? fallbackTitle)
                    .lineLimit(1)
                Text(album?.artistName ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(Color.lunara(.textSecondary))
                    .lineLimit(1)
            }

            Spacer()

            trailing()

            if album != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let album {
                selectedAlbum = album
            }
        }
        .task {
            if let album {
                viewModel.loadThumbnailIfNeeded(for: album)
            } else {
                // Freshly queued: no offline tracks yet, so resolve the album's
                // metadata directly — the row re-renders with title/artist/art
                // the moment it lands (Lunara-dhv).
                await viewModel.resolveActiveDownloadAlbum(albumID: albumID)
                if let resolved = viewModel.album(forActiveDownload: albumID) {
                    viewModel.loadThumbnailIfNeeded(for: resolved)
                }
            }
        }
    }

    @ViewBuilder
    private func rowThumbnail(albumID: String) -> some View {
        Group {
            if let url = viewModel.thumbnailURL(for: albumID) {
                DownsampledThumbnail(url: url, maxPixelSize: 132)
            } else {
                ZStack {
                    Color.lunara(.backgroundBase)
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.lunara(.textSecondary))
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .foregroundStyle(Color.lunara(.textSecondary))
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        default:
            Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                .font(.caption)
                .foregroundStyle(Color.lunara(.textSecondary))
        }
    }
}
