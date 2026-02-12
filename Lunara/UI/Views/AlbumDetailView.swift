import SwiftUI

struct AlbumDetailView: View {
    let album: PlexAlbum
    let albumRatingKeys: [String]
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let sessionInvalidationHandler: () -> Void
    @StateObject private var viewModel: AlbumDetailViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var albumTheme: AlbumTheme?
    @State private var isQueueingDownload = false
    @Environment(\.nowPlayingInsetHeight) private var nowPlayingInsetHeight

    enum Layout {
        static let globalPadding = LunaraTheme.Layout.globalPadding
        static let sectionSpacing = LunaraTheme.Layout.sectionSpacing
        static let cardCornerRadius = LunaraTheme.Layout.cardCornerRadius
        static let trackRowVerticalPadding: CGFloat = 12
        static let trackRowHorizontalPadding: CGFloat = 14
        static let trackRowSpacing: CGFloat = 10
        static let cardShadowOpacity: Double = 0.08
        static let cardShadowRadius: CGFloat = 8
        static let cardShadowYOffset: CGFloat = 1
        static let titleSpacing: CGFloat = 6
        static let metadataSpacing: CGFloat = 10
    }

    init(
        album: PlexAlbum,
        albumRatingKeys: [String] = [],
        playbackViewModel: PlaybackViewModel,
        sessionInvalidationHandler: @escaping () -> Void = {}
    ) {
        self.album = album
        self.albumRatingKeys = albumRatingKeys
        self.playbackViewModel = playbackViewModel
        self.sessionInvalidationHandler = sessionInvalidationHandler
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(
            album: album,
            albumRatingKeys: albumRatingKeys,
            sessionInvalidationHandler: sessionInvalidationHandler,
            playbackController: playbackViewModel
        ))
    }

    var body: some View {
        let basePalette = LunaraTheme.Palette.colors(for: colorScheme)
        let palette = ThemePalette(
            palette: basePalette
        )
        let themePalette = albumTheme.map(ThemePalette.init(theme:)) ?? palette
        let navTitleOpacity = navTitleOpacity(for: scrollOffset)

        ZStack {
            if let theme = albumTheme {
                ThemedBackgroundView(theme: theme)
            } else {
                LinenBackgroundView(palette: basePalette)
            }
            GeometryReader { proxy in
                ScrollView {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("albumScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                        AlbumArtworkView(album: album, palette: basePalette, size: .detail)
                            .frame(width: proxy.size.width, height: proxy.size.width)
                            .clipped()

                        titleBlock(palette: themePalette)
                            .padding(.horizontal, Layout.globalPadding)

                        if viewModel.isLoading {
                            ProgressView("Loading tracks...")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Layout.globalPadding)
                        } else if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundStyle(basePalette.stateError)
                                .padding(.horizontal, Layout.globalPadding)
                        } else {
                            VStack(alignment: .leading, spacing: Layout.trackRowSpacing) {
                                Text("Tracks")
                                    .font(LunaraTheme.Typography.displayBold(size: 22))
                                    .foregroundStyle(themePalette.textPrimary)

                                ForEach(viewModel.tracks, id: \.ratingKey) { track in
                                    TrackRowCard(
                                        track: track,
                                        albumArtist: album.artist,
                                        palette: themePalette,
                                        onTap: {
                                        viewModel.playTrack(track)
                                        },
                                        onPlayNow: {
                                            playbackViewModel.enqueueTrack(
                                                mode: .playNow,
                                                track: track,
                                                album: album,
                                                albumRatingKeys: albumRatingKeys,
                                                allTracks: viewModel.tracks,
                                                artworkRequest: artworkRequest()
                                            )
                                        },
                                        onPlayNext: {
                                            playbackViewModel.enqueueTrack(
                                                mode: .playNext,
                                                track: track,
                                                album: album,
                                                albumRatingKeys: albumRatingKeys,
                                                allTracks: viewModel.tracks,
                                                artworkRequest: artworkRequest()
                                            )
                                        },
                                        onPlayLater: {
                                            playbackViewModel.enqueueTrack(
                                                mode: .playLater,
                                                track: track,
                                                album: album,
                                                albumRatingKeys: albumRatingKeys,
                                                allTracks: viewModel.tracks,
                                                artworkRequest: artworkRequest()
                                            )
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, Layout.globalPadding)
                        }

                        metadataSection(palette: themePalette)
                            .padding(.horizontal, Layout.globalPadding)

                        genresSection(palette: themePalette)
                            .padding(.horizontal, Layout.globalPadding)

                        moodsSection(palette: themePalette)
                            .padding(.horizontal, Layout.globalPadding)

                        stylesSection(palette: themePalette)
                            .padding(.horizontal, Layout.globalPadding)

                        downloadButton(palette: themePalette)
                            .padding(.horizontal, Layout.globalPadding)
                    }
                    .padding(.bottom, Layout.globalPadding)
                }
                .safeAreaInset(edge: .bottom) {
                    if nowPlayingInsetHeight > 0 {
                        Color.clear.frame(height: nowPlayingInsetHeight)
                    }
                }
                .coordinateSpace(name: "albumScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(album.title)
                    .font(LunaraTheme.Typography.displayBold(size: 17))
                    .foregroundStyle(themePalette.textPrimary)
                    .lineLimit(1)
                    .opacity(navTitleOpacity)
                    .animation(.easeInOut(duration: 0.2), value: navTitleOpacity)
            }
        }
        .task {
            await viewModel.loadTracks()
            await viewModel.refreshDownloadProgress()
        }
        .overlay(alignment: .top) {
            if let message = playbackViewModel.errorMessage {
                PlaybackErrorBanner(message: message, palette: basePalette) {
                    playbackViewModel.clearError()
                }
                .padding(.horizontal, Layout.globalPadding)
            }
        }
        .task(id: album.ratingKey) {
            albumTheme = await albumThemeProvider()
        }
    }

    @ViewBuilder
    private func downloadButton(palette: ThemePalette) -> some View {
        let progress = viewModel.albumDownloadProgress
        let isDownloaded = progress?.isComplete == true
        let isDownloading = isQueueingDownload || (progress?.hasActiveWork == true)
        let buttonTitle = isDownloaded ? "Downloaded" : (isDownloading ? "Downloading..." : "Download Album")
        let symbol = isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle"
        let progressValue = progress?.fractionComplete ?? 0

        Button {
            guard isDownloaded == false, isDownloading == false else { return }
            isQueueingDownload = true
            Task {
                defer { isQueueingDownload = false }
                let keys = albumRatingKeys.isEmpty ? [album.ratingKey] : albumRatingKeys
                _ = try? await playbackViewModel.queueAlbumDownload(album: album, albumRatingKeys: keys)
                await viewModel.refreshDownloadProgress()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                    Text(buttonTitle)
                }
                .frame(maxWidth: .infinity)
                if isDownloading {
                    ProgressView(value: progressValue, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(palette.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlayButtonStyle(palette: palette))
        .disabled(isDownloaded || isDownloading)
    }

    @ViewBuilder
    private func titleBlock(palette: ThemePalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text(album.title)
                    .font(LunaraTheme.Typography.displayBold(size: 28))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let artistLine = artistLine {
                    if let artistRatingKey = album.parentRatingKey, !artistRatingKey.isEmpty {
                        NavigationLink {
                            ArtistDetailView(
                                artistRatingKey: artistRatingKey,
                                playbackViewModel: playbackViewModel,
                                sessionInvalidationHandler: sessionInvalidationHandler
                            )
                        } label: {
                            Text(artistLine)
                                .font(LunaraTheme.Typography.display(size: 16))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(artistLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
                    } else {
                        Text(artistLine)
                            .font(LunaraTheme.Typography.display(size: 16))
                            .foregroundStyle(palette.textSecondary)
                            .opacity(artistLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
                    }
                }

                Text(releaseDateLine)
                    .font(LunaraTheme.Typography.display(size: 14))
                    .foregroundStyle(palette.textSecondary)
                    .opacity(releaseDateLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
            }

            Spacer(minLength: 8)

            if let userRating = album.userRating {
                VStack(spacing: 10) {
                    StarRatingView(ratingOutOfTen: userRating, palette: palette)

                    HStack(spacing: 8) {
                        Button {
                            viewModel.playAlbum()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(PlayButtonStyle(palette: palette))
                        .accessibilityLabel("Play album")

                        Menu {
                            Button("Play Next") {
                                playbackViewModel.enqueueAlbum(mode: .playNext, album: album, albumRatingKeys: albumRatingKeys)
                            }
                            Button("Play Later") {
                                playbackViewModel.enqueueAlbum(mode: .playLater, album: album, albumRatingKeys: albumRatingKeys)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .frame(minWidth: 120, alignment: .center)
            } else {
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            viewModel.playAlbum()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(PlayButtonStyle(palette: palette))
                        .accessibilityLabel("Play album")

                        Menu {
                            Button("Play Next") {
                                playbackViewModel.enqueueAlbum(mode: .playNext, album: album, albumRatingKeys: albumRatingKeys)
                            }
                            Button("Play Later") {
                                playbackViewModel.enqueueAlbum(mode: .playLater, album: album, albumRatingKeys: albumRatingKeys)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metadataSection(palette: ThemePalette) -> some View {
        let metadataItems = metadataRows()
        if !metadataItems.isEmpty {
            VStack(alignment: .leading, spacing: Layout.metadataSpacing) {
                Text("Details")
                    .font(LunaraTheme.Typography.displayBold(size: 20))
                    .foregroundStyle(palette.textPrimary)

                ForEach(metadataItems, id: \.title) { item in
                    MetadataCard(title: item.title, value: item.value, palette: palette)
                }
            }
        }
    }

    @ViewBuilder
    private func genresSection(palette: ThemePalette) -> some View {
        let genres = album.genres?.map(\.tag).filter { !$0.isEmpty } ?? []
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
    private func moodsSection(palette: ThemePalette) -> some View {
        let moods = album.moods?.map(\.tag).filter { !$0.isEmpty } ?? []
        if !moods.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Moods")
                    .font(LunaraTheme.Typography.displayBold(size: 20))
                    .foregroundStyle(palette.textPrimary)

                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(moods, id: \.self) { mood in
                        GenrePillView(title: mood, palette: palette)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stylesSection(palette: ThemePalette) -> some View {
        let styles = album.styles?.map(\.tag).filter { !$0.isEmpty } ?? []
        if !styles.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Styles")
                    .font(LunaraTheme.Typography.displayBold(size: 20))
                    .foregroundStyle(palette.textPrimary)

                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(styles, id: \.self) { style in
                        GenrePillView(title: style, palette: palette)
                    }
                }
            }
        }
    }

    private var artistLine: String? {
        album.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var releaseDateLine: String {
        if let dateText = formattedReleaseDate() {
            return dateText
        }
        if let year = album.year {
            return String(year)
        }
        return "Release date unavailable"
    }

    private func formattedReleaseDate() -> String? {
        guard let dateString = album.originallyAvailableAt,
              let date = DateFormatter.iso8601Short.date(from: dateString) else {
            return nil
        }
        return DateFormatter.releaseLong.string(from: date)
    }

    private func metadataRows() -> [MetadataItem] {
        var rows: [MetadataItem] = []
        if let summary = album.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(MetadataItem(title: "Summary", value: summary))
        }
        if let rating = album.rating {
            rows.append(MetadataItem(title: "Rating", value: String(format: "%.1f", rating)))
        }
        if let userRating = album.userRating {
            rows.append(MetadataItem(title: "User Rating", value: String(format: "%.1f", userRating)))
        }
        return rows
    }

    private func navTitleOpacity(for offset: CGFloat) -> Double {
        let fadeStart: CGFloat = -60
        let fadeEnd: CGFloat = -140
        let progress = min(1, max(0, (offset - fadeStart) / (fadeEnd - fadeStart)))
        return Double(progress)
    }

    private func albumThemeProvider() async -> AlbumTheme? {
        guard let request = artworkRequest() else { return nil }
        return await ArtworkThemeProvider.shared.theme(for: request)
    }

    private func artworkRequest() -> ArtworkRequest? {
        guard let serverURL = UserDefaults.standard.string(forKey: "plex.server.baseURL"),
              let baseURL = URL(string: serverURL) else {
            return nil
        }
        let storedToken = try? PlexAuthTokenStore(keychain: KeychainStore()).load()
        guard let token = storedToken ?? nil else {
            return nil
        }
        let builder = ArtworkRequestBuilder(baseURL: baseURL, token: token)
        return builder.albumRequest(for: album, size: .detail)
    }
}

private struct TrackRowCard: View {
    let track: PlexTrack
    let albumArtist: String?
    let palette: ThemePalette
    let onTap: () -> Void
    let onPlayNow: () -> Void
    let onPlayNext: () -> Void
    let onPlayLater: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(track.index.map(String.init) ?? "-")
                    .font(LunaraTheme.Typography.displayRegular(size: 13).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(LunaraTheme.Typography.displayRegular(size: 17))
                        .foregroundStyle(palette.textPrimary)

                    if let trackArtist = trackArtistToShow {
                        Text(trackArtist)
                            .font(LunaraTheme.Typography.displayRegular(size: 13))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                if let duration = track.duration {
                    Text(formatDuration(duration))
                        .font(LunaraTheme.Typography.displayRegular(size: 13).monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.vertical, AlbumDetailView.Layout.trackRowVerticalPadding)
            .padding(.horizontal, AlbumDetailView.Layout.trackRowHorizontalPadding)
            .background(palette.raised)
            .overlay(
                RoundedRectangle(cornerRadius: AlbumDetailView.Layout.cardCornerRadius)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AlbumDetailView.Layout.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play Now") { onPlayNow() }
            Button("Play Next") { onPlayNext() }
            Button("Play Later") { onPlayLater() }
        }
    }

    private var trackArtistToShow: String? {
        let trackArtistRaw = cleaned(track.originalTitle ?? track.grandparentTitle)
        guard let trackArtistRaw, !trackArtistRaw.isEmpty else {
            return nil
        }
        let trackArtist = normalized(trackArtistRaw)
        let albumArtist = normalized(cleaned(albumArtist))
        if trackArtist == albumArtist {
            return nil
        }
        return trackArtistRaw
    }

    private func cleaned(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func normalized(_ value: String?) -> String? {
        value?.lowercased()
    }

    private func formatDuration(_ millis: Int) -> String {
        let totalSeconds = max(millis / 1000, 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PlayButtonStyle: ButtonStyle {
    let palette: ThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.accentPrimary.opacity(configuration.isPressed ? 0.22 : 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(palette.accentPrimary.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct MetadataCard: View {
    let title: String
    let value: String
    let palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(LunaraTheme.Typography.displayBold(size: 11))
                .foregroundStyle(palette.textSecondary)

            Text(value)
                .font(LunaraTheme.Typography.displayRegular(size: 15))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(palette.raised)
        .overlay(
            RoundedRectangle(cornerRadius: AlbumDetailView.Layout.cardCornerRadius)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AlbumDetailView.Layout.cardCornerRadius))
    }
}

private struct StarRatingView: View {
    let ratingOutOfTen: Double
    let palette: ThemePalette

    var body: some View {
        let ratingOutOfFive = max(0, min(ratingOutOfTen / 2.0, 5))
        let fullStars = Int(ratingOutOfFive)
        let hasHalfStar = ratingOutOfFive - Double(fullStars) >= 0.5
        let emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0)

        HStack(spacing: 4) {
            ForEach(0..<fullStars, id: \.self) { _ in
                Image(systemName: "star.fill")
            }
            if hasHalfStar {
                Image(systemName: "star.leadinghalf.filled")
            }
            ForEach(0..<emptyStars, id: \.self) { _ in
                Image(systemName: "star")
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(palette.accentSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.raised.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.accentSecondary.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        .accessibilityLabel("\(ratingOutOfFive, specifier: "%.1f") out of 5 stars")
    }
}

private struct MetadataItem {
    let title: String
    let value: String
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
