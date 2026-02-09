import SwiftUI

struct AlbumDetailView: View {
    let album: PlexAlbum
    let sessionInvalidationHandler: () -> Void
    @StateObject private var viewModel: AlbumDetailViewModel
    @Environment(\.colorScheme) private var colorScheme

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
    }

    init(album: PlexAlbum, sessionInvalidationHandler: @escaping () -> Void = {}) {
        self.album = album
        self.sessionInvalidationHandler = sessionInvalidationHandler
        _viewModel = StateObject(wrappedValue: AlbumDetailViewModel(
            album: album,
            sessionInvalidationHandler: sessionInvalidationHandler
        ))
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)

        ZStack {
            LinenBackgroundView(palette: palette)
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    headerCard(palette: palette)

                    if viewModel.isLoading {
                        ProgressView("Loading tracks...")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(palette.stateError)
                    } else {
                        VStack(alignment: .leading, spacing: Layout.trackRowSpacing) {
                            Text("Tracks")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            ForEach(viewModel.tracks, id: \.ratingKey) { track in
                                TrackRowCard(track: track, palette: palette)
                            }
                        }
                    }
                }
                .padding(Layout.globalPadding)
            }
        }
        .navigationTitle("Album")
        .task {
            await viewModel.loadTracks()
        }
    }

    @ViewBuilder
    private func headerCard(palette: LunaraTheme.PaletteColors) -> some View {
        HStack(spacing: 16) {
            AlbumArtworkView(album: album, palette: palette)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))

            VStack(alignment: .leading, spacing: 8) {
                Text(album.title)
                    .font(LunaraTheme.Typography.display(size: 28))
                    .foregroundStyle(palette.textPrimary)
                if let year = album.year {
                    Text(String(year))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(12)
        .background(palette.raised)
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .shadow(
            color: Color.black.opacity(Layout.cardShadowOpacity),
            radius: Layout.cardShadowRadius,
            x: 0,
            y: Layout.cardShadowYOffset
        )
    }
}

private struct TrackRowCard: View {
    let track: PlexTrack
    let palette: LunaraTheme.PaletteColors

    var body: some View {
        HStack(spacing: 10) {
            Text(track.index.map(String.init) ?? "-")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .frame(width: 22, alignment: .leading)

            Text(track.title)
                .font(.system(size: 17))
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 8)

            if let duration = track.duration {
                Text(formatDuration(duration))
                    .font(.system(size: 13).monospacedDigit())
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

    private func formatDuration(_ millis: Int) -> String {
        let totalSeconds = max(millis / 1000, 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
