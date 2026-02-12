import SwiftUI

struct ManageDownloadsView: View {
    @StateObject private var viewModel: ManageDownloadsViewModel
    @State private var isShowingStreamCachedTracks = false
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    init(
        playbackViewModel: PlaybackViewModel,
        signOut: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ManageDownloadsViewModel())
        self.playbackViewModel = playbackViewModel
        self.signOut = signOut
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

        ZStack {
            LinenBackgroundView(palette: palette)
            List {
                inProgressSection(palette: palette)
                downloadedAlbumsSection(palette: palette)
                downloadedCollectionsSection(palette: palette)
                streamCachedSection(palette: palette)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Manage Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                PlaybackErrorBanner(message: error, palette: palette) {
                    viewModel.clearError()
                }
                .padding(.horizontal, LunaraTheme.Layout.globalPadding)
            }
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func inProgressSection(palette: LunaraTheme.PaletteColors) -> some View {
        let queue = viewModel.snapshot.queue
        Section("In Progress") {
            if queue.pendingTracks.isEmpty && queue.inProgressTracks.isEmpty {
                Text("No active downloads.")
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(queue.inProgressTracks, id: \.trackRatingKey) { progress in
                    downloadRow(track: progress, palette: palette, isPending: false)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Cancel", role: .destructive) {
                            Task { await viewModel.cancel(trackRatingKey: progress.trackRatingKey) }
                        }
                    }
                }

                ForEach(queue.pendingTracks, id: \.trackRatingKey) { track in
                    downloadRow(track: track, palette: palette, isPending: true)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Cancel", role: .destructive) {
                                Task { await viewModel.cancel(trackRatingKey: track.trackRatingKey) }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func downloadedAlbumsSection(palette: LunaraTheme.PaletteColors) -> some View {
        Section("Downloaded Albums") {
            if viewModel.snapshot.downloadedAlbums.isEmpty {
                Text("No downloaded albums.")
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(viewModel.snapshot.downloadedAlbums) { album in
                    Group {
                        if let destination = albumDestination(for: album) {
                            NavigationLink {
                                destination
                            } label: {
                                downloadedAlbumRow(album: album, palette: palette)
                            }
                            .buttonStyle(.plain)
                        } else {
                            downloadedAlbumRow(album: album, palette: palette)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove", role: .destructive) {
                            Task { await viewModel.removeAlbum(albumIdentity: album.albumIdentity) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func downloadedCollectionsSection(palette: LunaraTheme.PaletteColors) -> some View {
        Section("Downloaded Collections") {
            if viewModel.snapshot.downloadedCollections.isEmpty {
                Text("No downloaded collections.")
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(viewModel.snapshot.downloadedCollections) { collection in
                    Group {
                        if let destination = collectionDestination(for: collection) {
                            NavigationLink {
                                destination
                            } label: {
                                downloadedCollectionRow(collection: collection, palette: palette)
                            }
                            .buttonStyle(.plain)
                        } else {
                            downloadedCollectionRow(collection: collection, palette: palette)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove", role: .destructive) {
                            Task { await viewModel.removeCollection(collectionKey: collection.collectionKey) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func downloadedAlbumRow(
        album: OfflineDownloadedAlbumSummary,
        palette: LunaraTheme.PaletteColors
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            artworkThumbnail(path: album.artworkPath, palette: palette)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.displayTitle)
                    .foregroundStyle(palette.textPrimary)
                if let artist = album.artistName, artist.isEmpty == false {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("\(album.completedTrackCount)/\(album.totalTrackCount) tracks")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func downloadedCollectionRow(
        collection: OfflineDownloadedCollectionSummary,
        palette: LunaraTheme.PaletteColors
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(collection.title)
            Text("\(collection.albumCount) albums")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private func streamCachedSection(palette: LunaraTheme.PaletteColors) -> some View {
        Section("Stream-Cached") {
            if viewModel.snapshot.streamCachedTracks.isEmpty {
                Text("No stream-cached tracks.")
                    .foregroundStyle(palette.textSecondary)
            } else {
                DisclosureGroup(
                    isExpanded: $isShowingStreamCachedTracks,
                    content: {
                        ForEach(viewModel.snapshot.streamCachedTracks) { track in
                            streamCachedTrackRow(track: track, palette: palette)
                        }
                    },
                    label: {
                        Text("\(viewModel.snapshot.streamCachedTracks.count) cached tracks")
                            .foregroundStyle(palette.textPrimary)
                    }
                )
                .tint(palette.textPrimary)
            }
        }
    }

    @ViewBuilder
    private func streamCachedTrackRow(
        track: OfflineStreamCachedTrackSummary,
        palette: LunaraTheme.PaletteColors
    ) -> some View {
        let trimmedTitle = track.trackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = (trimmedTitle?.isEmpty == false) ? (trimmedTitle ?? "Unknown Track") : "Unknown Track"

        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .foregroundStyle(palette.textPrimary)
            if let artist = track.artistName?.trimmingCharacters(in: .whitespacesAndNewlines), artist.isEmpty == false {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text("Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func downloadRow(
        track: OfflineTrackProgress,
        palette: LunaraTheme.PaletteColors,
        isPending: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            artworkThumbnail(path: track.artworkPath, palette: palette)

            VStack(alignment: .leading, spacing: 4) {
                let primaryTitle = track.trackTitle ?? track.albumTitle ?? track.trackRatingKey
                Text(primaryTitle)
                    .foregroundStyle(palette.textPrimary)
                if let albumTitle = track.albumTitle,
                   albumTitle.isEmpty == false,
                   albumTitle != primaryTitle {
                    Text(albumTitle)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                if let artist = track.artistName, artist.isEmpty == false {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                if isPending {
                    Text("Queued")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                } else if let expected = track.expectedBytes, expected > 0 {
                    ProgressView(value: Double(track.bytesReceived), total: Double(expected))
                    Text(progressDetails(for: track))
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ProgressView()
                    Text(progressDetails(for: track))
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func progressDetails(for track: OfflineTrackProgress) -> String {
        let downloaded = byteFormatter.string(fromByteCount: track.bytesReceived)
        var parts: [String] = [downloaded]

        if let expected = track.expectedBytes, expected > 0 {
            let total = byteFormatter.string(fromByteCount: expected)
            parts[0] = "\(downloaded) / \(total)"
        }
        if let bytesPerSecond = track.bytesPerSecond, bytesPerSecond > 0 {
            let speed = byteFormatter.string(fromByteCount: Int64(bytesPerSecond))
            parts.append("\(speed)/s")
        }
        if let remaining = track.estimatedRemainingSeconds, remaining.isFinite {
            parts.append("ETA \(formattedRemainingTime(remaining))")
        }
        return parts.joined(separator: " • ")
    }

    private func formattedRemainingTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded(.up))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        if minutes > 59 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return String(format: "%02d:%02d:%02d", hours, remMinutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    @ViewBuilder
    private func artworkThumbnail(path: String?, palette: LunaraTheme.PaletteColors) -> some View {
        if let request = artworkRequest(path: path) {
            ArtworkView(
                request: request,
                placeholder: palette.raised,
                secondaryText: palette.textSecondary
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .clipped()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.raised)
                .frame(width: 44, height: 44)
        }
    }

    private func artworkRequest(path: String?) -> ArtworkRequest? {
        guard let path, path.isEmpty == false else { return nil }
        guard let serverURL = UserDefaults.standard.string(forKey: "plex.server.baseURL"),
              let baseURL = URL(string: serverURL) else {
            return nil
        }
        let storedToken = try? PlexAuthTokenStore(keychain: KeychainStore()).load()
        guard let token = storedToken ?? nil else {
            return nil
        }
        let builder = PlexArtworkURLBuilder(baseURL: baseURL, token: token, maxSize: ArtworkSize.grid.maxPixelSize)
        let url = builder.makeTranscodedArtworkURL(artPath: path)
        let key = ArtworkCacheKey(ratingKey: path, artworkPath: path, size: .grid)
        return ArtworkRequest(key: key, url: url)
    }

    private func albumDestination(for album: OfflineDownloadedAlbumSummary) -> AlbumDetailView? {
        guard let albumRatingKey = album.albumRatingKeys.first else { return nil }
        guard let plexAlbum = viewModel.albumsByRatingKey[albumRatingKey] else { return nil }
        return AlbumDetailView(
            album: plexAlbum,
            albumRatingKeys: album.albumRatingKeys,
            playbackViewModel: playbackViewModel,
            sessionInvalidationHandler: signOut
        )
    }

    private func collectionDestination(
        for collection: OfflineDownloadedCollectionSummary
    ) -> CollectionDetailView? {
        guard let plexCollection = viewModel.collectionsByKey[collection.collectionKey] else { return nil }
        guard let sectionKey = viewModel.musicSectionKey, sectionKey.isEmpty == false else { return nil }
        return CollectionDetailView(
            collection: plexCollection,
            sectionKey: sectionKey,
            playbackViewModel: playbackViewModel,
            signOut: signOut
        )
    }
}
