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

            GeometryReader { proxy in
                let contentWidth = max(proxy.size.width - (Layout.globalPadding * 2), 0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        artworkSection

                    titleSection(contentWidth: contentWidth)

                        controlsSection

                        scrubberSection

                        upNextSection
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, Layout.globalPadding)
                    .padding(.bottom, Layout.globalPadding)
                    .padding(.top, 16)
                }
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
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Group {
                        if let album = context?.album {
                            AlbumArtworkView(album: album, palette: nil, size: .detail)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            RoundedRectangle(cornerRadius: Layout.artworkCornerRadius)
                                .fill(palette.raised)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Layout.artworkCornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func titleSection(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MarqueeText(
                text: state.trackTitle,
                font: LunaraTheme.Typography.displayBold(size: 28),
                color: palette.textPrimary,
                containerWidth: contentWidth
            )

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
                .foregroundStyle(palette.textPrimary)
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

private struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let containerWidth: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var startDate = Date()

    private enum Timing {
        static let startHold: TimeInterval = 1.0
        static let endHold: TimeInterval = 1.0
        static let forwardSpeed: CGFloat = 28
        static let returnSpeed: CGFloat = 60
        static let tickRate: TimeInterval = 1.0 / 30.0
        static let minForwardDuration: TimeInterval = 2.5
        static let minReturnDuration: TimeInterval = 1.2
        static let extraGap: CGFloat = 60
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Timing.tickRate)) { context in
            let effectiveWidth = max(containerWidth, 0)
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset(at: context.date))
            }
            .frame(width: effectiveWidth, alignment: .leading)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(WidthReader(key: TextWidthKey.self))
                    .hidden()
            }
            .clipped()
            .onPreferenceChange(TextWidthKey.self) { width in
                if textWidth != width {
                    textWidth = width
                    resetCycle()
                }
            }
            .onChange(of: containerWidth) { _, _ in
                resetCycle()
            }
            .onChange(of: text) { _, _ in
                resetCycle()
            }
        }
    }

    private var shouldScroll: Bool {
        textWidth > containerWidth && containerWidth > 0
    }

    private var scrollDistance: CGFloat {
        max(textWidth - containerWidth + Timing.extraGap, 0)
    }

    private func resetCycle() {
        startDate = Date()
    }

    private func offset(at date: Date) -> CGFloat {
        guard shouldScroll, scrollDistance > 0 else { return 0 }

        let forwardDuration = max(
            Timing.minForwardDuration,
            TimeInterval(scrollDistance / Timing.forwardSpeed)
        )
        let returnDuration = max(
            Timing.minReturnDuration,
            TimeInterval(scrollDistance / Timing.returnSpeed)
        )
        let cycleDuration = Timing.startHold + forwardDuration + Timing.endHold + returnDuration
        guard cycleDuration > 0 else { return 0 }

        let elapsed = date.timeIntervalSince(startDate)
        let t = elapsed.truncatingRemainder(dividingBy: cycleDuration)

        if t < Timing.startHold {
            return 0
        }

        let forwardStart = Timing.startHold
        let forwardEnd = Timing.startHold + forwardDuration
        if t < forwardEnd {
            let progress = (t - forwardStart) / forwardDuration
            return -scrollDistance * progress
        }

        let endHoldEnd = forwardEnd + Timing.endHold
        if t < endHoldEnd {
            return -scrollDistance
        }

        let backProgress = (t - endHoldEnd) / returnDuration
        return -scrollDistance + (scrollDistance * backProgress)
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct WidthReader<Key: PreferenceKey>: View where Key.Value == CGFloat {
    var key: Key.Type

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.width)
        }
    }
}

private struct UpNextRow: View {
    let track: PlexTrack
    let albumArtist: String?
    let palette: ThemePalette
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Text(trackNumber)
                    .font(LunaraTheme.Typography.displayRegular(size: 13).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(LunaraTheme.Typography.displayRegular(size: 16))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

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
