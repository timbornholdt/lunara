import SwiftUI

struct ArtistDetailView: View {
    let artistRatingKey: String
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let sessionInvalidationHandler: () -> Void
    @StateObject private var viewModel: ArtistDetailViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.nowPlayingInsetHeight) private var nowPlayingInsetHeight
    @State private var isBioExpanded = false

    enum Layout {
        static let globalPadding = LunaraTheme.Layout.globalPadding
        static let sectionSpacing = LunaraTheme.Layout.sectionSpacing
        static let cardCornerRadius = LunaraTheme.Layout.cardCornerRadius
        static let heroCornerRadius: CGFloat = 18
        static let heroHeight: CGFloat = 220
        static let albumRowSpacing: CGFloat = 12
    }

    init(
        artistRatingKey: String,
        playbackViewModel: PlaybackViewModel,
        sessionInvalidationHandler: @escaping () -> Void = {}
    ) {
        self.artistRatingKey = artistRatingKey
        self.playbackViewModel = playbackViewModel
        self.sessionInvalidationHandler = sessionInvalidationHandler
        _viewModel = StateObject(wrappedValue: ArtistDetailViewModel(
            artistRatingKey: artistRatingKey,
            sessionInvalidationHandler: sessionInvalidationHandler,
            playbackController: playbackViewModel
        ))
    }

    var body: some View {
        let basePalette = LunaraTheme.Palette.colors(for: colorScheme)
        let themePalette = ThemePalette(palette: basePalette)

        ZStack {
            LinenBackgroundView(palette: basePalette)
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    heroSection(palette: basePalette)

                    if let artist = viewModel.artist {
                        titleSection(artist: artist, palette: themePalette)
                        actionButtons(palette: themePalette)
                        genresSection(artist: artist, palette: themePalette)
                    }

                    albumsSection(palette: themePalette, basePalette: basePalette)
                }
                .padding(.horizontal, Layout.globalPadding)
                .padding(.bottom, Layout.globalPadding)
            }
            .safeAreaInset(edge: .bottom) {
                if nowPlayingInsetHeight > 0 {
                    Color.clear.frame(height: nowPlayingInsetHeight)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.artist?.title ?? "Artist")
                    .font(LunaraTheme.Typography.displayBold(size: 17))
                    .foregroundStyle(themePalette.textPrimary)
            }
        }
        .overlay(alignment: .top) {
            if let message = playbackViewModel.errorMessage {
                PlaybackErrorBanner(message: message, palette: basePalette) {
                    playbackViewModel.clearError()
                }
                .padding(.horizontal, Layout.globalPadding)
            }
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func heroSection(palette: LunaraTheme.PaletteColors) -> some View {
        if let artist = viewModel.artist,
           artistArtworkRequest(for: artist) != nil {
            ArtistArtworkView(artist: artist, palette: palette, size: .detail)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.heroHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Layout.heroCornerRadius))
        } else {
            LinenBackgroundView(palette: palette)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.heroHeight)
                .clipShape(RoundedRectangle(cornerRadius: Layout.heroCornerRadius))
        }
    }

    private func artistArtworkRequest(for artist: PlexArtist) -> ArtworkRequest? {
        guard let serverURL = UserDefaults.standard.string(forKey: "plex.server.baseURL"),
              let baseURL = URL(string: serverURL) else {
            return nil
        }
        let storedToken = try? PlexAuthTokenStore(keychain: KeychainStore()).load()
        guard let token = storedToken ?? nil else {
            return nil
        }
        let builder = ArtworkRequestBuilder(baseURL: baseURL, token: token)
        return builder.artistRequest(for: artist, size: .detail)
    }

    @ViewBuilder
    private func titleSection(artist: PlexArtist, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(artist.title)
                .font(LunaraTheme.Typography.displayBold(size: 28))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = artist.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(summary)
                    .font(LunaraTheme.Typography.displayRegular(size: 15))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(isBioExpanded ? nil : 4)

                Button(isBioExpanded ? "Show less" : "Read more") {
                    isBioExpanded.toggle()
                }
                .font(LunaraTheme.Typography.displayRegular(size: 13))
                .foregroundStyle(palette.accentPrimary)
            }
        }
    }

    @ViewBuilder
    private func actionButtons(palette: ThemePalette) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.playAll() }
            } label: {
                Label("Play All", systemImage: "play.fill")
            }
            .buttonStyle(ArtistActionButtonStyle(palette: palette))

            Button {
                Task { await viewModel.shuffle() }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(ArtistActionButtonStyle(palette: palette))
        }
    }

    @ViewBuilder
    private func genresSection(artist: PlexArtist, palette: ThemePalette) -> some View {
        let genres = artist.genres?.map(\.tag).filter { !$0.isEmpty } ?? []
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Genres")
                    .font(LunaraTheme.Typography.displayBold(size: 20))
                    .foregroundStyle(palette.textPrimary)

                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(genres, id: \.self) { genre in
                        GenrePillView(title: genre, palette: palette)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func albumsSection(palette: ThemePalette, basePalette: LunaraTheme.PaletteColors) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Albums")
                .font(LunaraTheme.Typography.displayBold(size: 22))
                .foregroundStyle(palette.textPrimary)

            if viewModel.isLoading {
                ProgressView("Loading albums...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(palette.textSecondary)
            } else if viewModel.albums.isEmpty {
                Text("No albums found.")
                    .font(LunaraTheme.Typography.displayRegular(size: 14))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(viewModel.albums, id: \.ratingKey) { album in
                    NavigationLink {
                        AlbumDetailView(
                            album: album,
                            albumRatingKeys: [album.ratingKey],
                            playbackViewModel: playbackViewModel,
                            sessionInvalidationHandler: sessionInvalidationHandler
                        )
                    } label: {
                        ArtistAlbumRowView(album: album, palette: palette, basePalette: basePalette)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            playbackViewModel.enqueueAlbum(
                                mode: .playNow,
                                album: album,
                                albumRatingKeys: [album.ratingKey]
                            )
                        } label: {
                            Label("Play Now", systemImage: "play.fill")
                        }
                        Button {
                            playbackViewModel.enqueueAlbum(
                                mode: .playNext,
                                album: album,
                                albumRatingKeys: [album.ratingKey]
                            )
                        } label: {
                            Label("Play Next", systemImage: "text.insert")
                        }
                        Button {
                            playbackViewModel.enqueueAlbum(
                                mode: .playLater,
                                album: album,
                                albumRatingKeys: [album.ratingKey]
                            )
                        } label: {
                            Label("Play Later", systemImage: "text.append")
                        }
                        Button {
                            playbackViewModel.downloadAlbum(
                                album: album,
                                albumRatingKeys: [album.ratingKey]
                            )
                        } label: {
                            Label("Download Album", systemImage: "arrow.down.circle")
                        }
                    }
                }
            }
        }
    }

}

private struct ArtistAlbumRowView: View {
    let album: PlexAlbum
    let palette: ThemePalette
    let basePalette: LunaraTheme.PaletteColors

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtworkView(album: album, palette: basePalette, size: .grid)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(LunaraTheme.Typography.displayBold(size: 16))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)

                if !metadataLine.isEmpty {
                    Text(metadataLine)
                        .font(LunaraTheme.Typography.displayRegular(size: 13))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let userRating = album.userRating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                    Text(String(format: "%.1f", userRating / 2.0))
                }
                .font(LunaraTheme.Typography.displayRegular(size: 12))
                .foregroundStyle(palette.accentSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(palette.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(palette.raised)
        .overlay(
            RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius))
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let releaseDate = releaseDateText {
            parts.append(releaseDate)
        } else if let year = album.year {
            parts.append(String(year))
        }
        if let duration = album.duration {
            parts.append(formatDuration(duration))
        }
        return parts.joined(separator: " • ")
    }

    private var releaseDateText: String? {
        guard let dateString = album.originallyAvailableAt,
              let date = DateFormatter.iso8601Short.date(from: dateString) else {
            return nil
        }
        return DateFormatter.releaseLong.string(from: date)
    }

    private func formatDuration(_ millis: Int) -> String {
        let totalSeconds = max(millis / 1000, 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remainder, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ArtistActionButtonStyle: ButtonStyle {
    let palette: ThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(palette.accentPrimary.opacity(configuration.isPressed ? 0.22 : 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(palette.accentPrimary.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private extension DateFormatter {
    static let iso8601Short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let releaseLong: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}
