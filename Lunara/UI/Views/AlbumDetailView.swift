import SwiftUI

struct AlbumDetailView: View {
    let album: PlexAlbum
    let albumRatingKeys: [String]
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let sessionInvalidationHandler: () -> Void
    @StateObject private var viewModel: AlbumDetailViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var scrollOffset: CGFloat = 0

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
        let palette = LunaraTheme.Palette.colors(for: colorScheme)
        let navTitleOpacity = navTitleOpacity(for: scrollOffset)

        ZStack {
            LinenBackgroundView(palette: palette)
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
                        AlbumArtworkView(album: album, palette: palette)
                            .frame(width: proxy.size.width, height: proxy.size.width)
                            .clipped()

                        titleBlock(palette: palette)
                            .padding(.horizontal, Layout.globalPadding)

                        if viewModel.isLoading {
                            ProgressView("Loading tracks...")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Layout.globalPadding)
                        } else if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundStyle(palette.stateError)
                                .padding(.horizontal, Layout.globalPadding)
                        } else {
                            VStack(alignment: .leading, spacing: Layout.trackRowSpacing) {
                                Text("Tracks")
                                    .font(LunaraTheme.Typography.displayBold(size: 22))
                                    .foregroundStyle(palette.textPrimary)

                                ForEach(viewModel.tracks, id: \.ratingKey) { track in
                                    TrackRowCard(track: track, palette: palette) {
                                        viewModel.playTrack(track)
                                    }
                                }
                            }
                            .padding(.horizontal, Layout.globalPadding)
                        }

                        metadataSection(palette: palette)
                            .padding(.horizontal, Layout.globalPadding)
                    }
                    .padding(.bottom, Layout.globalPadding)
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
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .opacity(navTitleOpacity)
                    .animation(.easeInOut(duration: 0.2), value: navTitleOpacity)
            }
        }
        .task {
            await viewModel.loadTracks()
        }
        .safeAreaInset(edge: .bottom) {
            if let nowPlaying = playbackViewModel.nowPlaying {
                NowPlayingBarView(
                    state: nowPlaying,
                    palette: palette,
                    onTogglePlayPause: { playbackViewModel.togglePlayPause() }
                )
                    .padding(.horizontal, Layout.globalPadding)
                    .padding(.bottom, Layout.globalPadding)
            }
        }
        .overlay(alignment: .top) {
            if let message = playbackViewModel.errorMessage {
                PlaybackErrorBanner(message: message, palette: palette) {
                    playbackViewModel.clearError()
                }
                .padding(.horizontal, Layout.globalPadding)
            }
        }
    }

    @ViewBuilder
    private func titleBlock(palette: LunaraTheme.PaletteColors) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text(album.title)
                    .font(LunaraTheme.Typography.displayBold(size: 28))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitleText)
                    .font(LunaraTheme.Typography.display(size: 15))
                    .foregroundStyle(palette.textSecondary)
                    .opacity(subtitleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if let userRating = album.userRating {
                    StarRatingView(ratingOutOfTen: userRating, palette: palette)
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[.top]
                        }
                }

                Button {
                    viewModel.playAlbum()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(PlayButtonStyle(palette: palette))
                .accessibilityLabel("Play album")
            }
        }
    }

    @ViewBuilder
    private func metadataSection(palette: LunaraTheme.PaletteColors) -> some View {
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

    private var subtitleText: String {
        let artist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = album.year.map(String.init)
        switch (artist?.isEmpty == false ? artist : nil, year) {
        case let (.some(name), .some(yearValue)):
            return "\(name) — \(yearValue)"
        case let (.some(name), .none):
            return name
        case let (.none, .some(yearValue)):
            return yearValue
        default:
            return " "
        }
    }

    private func metadataRows() -> [MetadataItem] {
        var rows: [MetadataItem] = []
        if let summary = album.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(MetadataItem(title: "Summary", value: summary))
        }
        if let genres = album.genres?.map(\.tag).filter({ !$0.isEmpty }), !genres.isEmpty {
            rows.append(MetadataItem(title: "Genres", value: genres.joined(separator: " · ")))
        }
        if let styles = album.styles?.map(\.tag).filter({ !$0.isEmpty }), !styles.isEmpty {
            rows.append(MetadataItem(title: "Styles", value: styles.joined(separator: " · ")))
        }
        if let moods = album.moods?.map(\.tag).filter({ !$0.isEmpty }), !moods.isEmpty {
            rows.append(MetadataItem(title: "Moods", value: moods.joined(separator: " · ")))
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
}

private struct TrackRowCard: View {
    let track: PlexTrack
    let palette: LunaraTheme.PaletteColors
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(track.index.map(String.init) ?? "-")
                    .font(LunaraTheme.Typography.displayRegular(size: 13).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22, alignment: .leading)

                Text(track.title)
                    .font(LunaraTheme.Typography.displayRegular(size: 17))
                    .foregroundStyle(palette.textPrimary)

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
    }

    private func formatDuration(_ millis: Int) -> String {
        let totalSeconds = max(millis / 1000, 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PlayButtonStyle: ButtonStyle {
    let palette: LunaraTheme.PaletteColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.accentPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.raised.opacity(configuration.isPressed ? 0.94 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct MetadataCard: View {
    let title: String
    let value: String
    let palette: LunaraTheme.PaletteColors

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
    let palette: LunaraTheme.PaletteColors

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
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(palette.accentSecondary)
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
