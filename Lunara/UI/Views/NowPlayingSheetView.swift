import SwiftUI

struct NowPlayingSheetView: View {
    let state: NowPlayingState
    let context: NowPlayingContext?
    let palette: ThemePalette
    let theme: AlbumTheme?
    let onTogglePlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onSelectTrack: (PlexTrack) -> Void
    let onNavigateToAlbum: () -> Void

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var pendingSeekTarget: Double?

    private enum Layout {
        static let globalPadding = LunaraTheme.Layout.globalPadding
        static let artworkCornerRadius = LunaraTheme.Layout.cardCornerRadius
        static let controlIconSize: CGFloat = 22
        static let controlTapSize: CGFloat = 44
        static let controlSpacing: CGFloat = 26
    }

    var body: some View {
        ZStack {
            ThemedBackgroundView(theme: theme ?? AlbumTheme.fallback())

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    artworkSection

                    titleSection

                    controlsSection

                    scrubberSection

                    upNextSection
                }
                .padding(.horizontal, Layout.globalPadding)
                .padding(.bottom, Layout.globalPadding)
                .padding(.top, 16)
            }
        }
        .onAppear {
            scrubValue = state.elapsedTime
        }
        .onChange(of: state.elapsedTime) { _, newValue in
            if let pending = pendingSeekTarget {
                if abs(newValue - pending) <= 1 {
                    pendingSeekTarget = nil
                } else {
                    return
                }
            }
            guard !isScrubbing else { return }
            scrubValue = newValue
        }
    }

    private var artworkSection: some View {
        Button(action: onNavigateToAlbum) {
            ZStack {
                if let album = context?.album {
                    AlbumArtworkView(album: album, palette: nil, size: .detail)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.artworkCornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: Layout.artworkCornerRadius)
                        .fill(palette.raised)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.trackTitle)
                .font(LunaraTheme.Typography.displayBold(size: 28))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)

            Text(context?.album.title ?? "Unknown Album")
                .font(LunaraTheme.Typography.displayRegular(size: 17))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)

            Text(context?.album.artist ?? "Unknown Artist")
                .font(LunaraTheme.Typography.displayRegular(size: 15))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
    }

    private var controlsSection: some View {
        HStack(spacing: Layout.controlSpacing) {
            controlButton(systemName: "backward.fill", action: onPrevious)
            controlButton(systemName: state.isPlaying ? "pause.fill" : "play.fill", action: onTogglePlayPause)
            controlButton(systemName: "forward.fill", action: onNext)
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Layout.controlIconSize, weight: .semibold))
                .foregroundStyle(palette.accentPrimary)
                .frame(width: Layout.controlTapSize, height: Layout.controlTapSize)
        }
        .buttonStyle(.plain)
    }

    private var scrubberSection: some View {
        VStack(spacing: 8) {
            Slider(
                value: $scrubValue,
                in: 0...(state.duration ?? max(scrubValue, 1)),
                onEditingChanged: handleScrubState
            )
            .tint(palette.accentPrimary)

            HStack {
                Text(formatTime(isScrubbing ? scrubValue : state.elapsedTime))
                Spacer()
                Text(formatTime(state.duration ?? 0))
            }
            .font(LunaraTheme.Typography.displayRegular(size: 13).monospacedDigit())
            .foregroundStyle(palette.textSecondary)
        }
    }

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Up Next")
                .font(LunaraTheme.Typography.displayBold(size: 18))
                .foregroundStyle(palette.textPrimary)

            let tracks = NowPlayingUpNextBuilder.upNextTracks(
                tracks: context?.tracks ?? [],
                currentRatingKey: state.trackRatingKey
            )

            if tracks.isEmpty {
                Text("No more tracks.")
                    .font(LunaraTheme.Typography.displayRegular(size: 14))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(tracks, id: \.ratingKey) { track in
                    UpNextRow(
                        track: track,
                        albumArtist: context?.album.artist,
                        palette: palette,
                        onTap: { onSelectTrack(track) }
                    )
                }
            }
        }
    }

    private func handleScrubState(_ editing: Bool) {
        if editing {
            isScrubbing = true
        } else {
            isScrubbing = false
            let target = scrubValue
            let current = state.elapsedTime
            if NowPlayingSeekDecision.shouldSeek(
                currentTime: current,
                targetTime: target,
                tolerance: 5
            ) {
                pendingSeekTarget = target
                onSeek(target)
            } else {
                pendingSeekTarget = nil
                scrubValue = current
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let minutes = totalSeconds / 60
        let remaining = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

private struct UpNextRow: View {
    let track: PlexTrack
    let albumArtist: String?
    let palette: ThemePalette
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(trackNumber)
                    .font(LunaraTheme.Typography.displayRegular(size: 13).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(LunaraTheme.Typography.displayRegular(size: 16))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    if let artist = TrackArtistDisplayResolver.displayArtist(for: track, albumArtist: albumArtist) {
                        Text(artist)
                            .font(LunaraTheme.Typography.displayRegular(size: 13))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let duration = track.duration {
                    Text(formatDuration(duration))
                        .font(LunaraTheme.Typography.displayRegular(size: 13).monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(palette.raised.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LunaraTheme.Layout.cardCornerRadius))
        }
        .buttonStyle(.plain)
    }

    private var trackNumber: String {
        if let index = track.index {
            return String(format: "%02d", index)
        }
        return "--"
    }

    private func formatDuration(_ millis: Int) -> String {
        let totalSeconds = max(millis / 1000, 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
