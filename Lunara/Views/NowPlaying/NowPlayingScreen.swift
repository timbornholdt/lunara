import SwiftUI
import UIKit

struct NowPlayingScreen: View {
    let viewModel: NowPlayingScreenViewModel
    var onNavigateToAlbum: ((Album) -> Void)?
    var onNavigateToArtist: ((Artist) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            viewModel.palette.background
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)

            ScrollView {
                VStack(spacing: 24) {
                    dragHandle
                    artworkSection
                    trackInfoSection
                    NowPlayingSeekBar(viewModel: viewModel)
                    transportControls
                    upNextSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(viewModel.palette.textSecondary.opacity(0.4))
            .frame(width: 36, height: 5)
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        Group {
            if let uiImage = viewModel.artworkImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } else {
                artworkPlaceholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onTapGesture {
            navigateToAlbum()
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(viewModel.palette.textSecondary.opacity(0.15))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(viewModel.palette.textSecondary)
            }
    }

    // MARK: - Track Info

    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.trackTitle ?? "Not Playing")
                .font(titleFont())
                .foregroundStyle(viewModel.palette.textPrimary)
                .lineLimit(2)
                .animation(.easeInOut(duration: 0.4), value: viewModel.palette)

            if let artist = viewModel.artistName {
                Button {
                    navigateToArtist()
                } label: {
                    Text(artist)
                        .font(subtitleFont())
                        .foregroundStyle(viewModel.palette.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }

            if let albumTitle = viewModel.albumTitle {
                Button {
                    navigateToAlbum()
                } label: {
                    Text(albumTitle)
                        .font(subtitleFont())
                        .foregroundStyle(viewModel.palette.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }


        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 40) {
            Button { viewModel.skipBack() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(viewModel.palette.textPrimary)
            }
            .buttonStyle(.plain)

            playPauseButton
                .frame(width: 64, height: 64)

            Button { viewModel.skipForward() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(viewModel.palette.textPrimary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var playPauseButton: some View {
        switch viewModel.playbackState {
        case .buffering:
            ProgressView()
                .tint(viewModel.palette.textPrimary)
                .scaleEffect(1.5)

        case .playing:
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(viewModel.palette.textPrimary)
            }
            .buttonStyle(.plain)

        default:
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(viewModel.palette.textPrimary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Up Next

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.upNextItems.isEmpty {
                Text("Up Next")
                    .font(sectionFont())
                    .foregroundStyle(viewModel.palette.textPrimary)

                LazyVStack(spacing: 8) {
                    ForEach(viewModel.upNextItems) { item in
                        upNextRow(item)
                    }
                }
            }
        }
    }

    private func upNextRow(_ item: NowPlayingScreenViewModel.UpNextItem) -> some View {
        HStack(spacing: 12) {
            Group {
                if let uiImage = item.artworkImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    upNextPlaceholder
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.trackTitle)
                    .font(upNextTitleFont())
                    .foregroundStyle(viewModel.palette.textPrimary)
                    .lineLimit(1)
                Text(item.artistName)
                    .font(upNextSubtitleFont())
                    .foregroundStyle(viewModel.palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var upNextPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(viewModel.palette.textSecondary.opacity(0.15))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.palette.textSecondary)
            }
    }

    // MARK: - Helpers

    private func navigateToAlbum() {
        guard let album = viewModel.currentAlbum else { return }
        dismiss()
        onNavigateToAlbum?(album)
    }

    private func navigateToArtist() {
        guard let artist = viewModel.currentArtist else { return }
        dismiss()
        onNavigateToArtist?(artist)
    }

    private func titleFont() -> Font {
        let token = LunaraVisualTokens.headingToken(for: .title, weight: .semibold)
        if UIFont(name: token.preferredFontName, size: token.size) != nil {
            return .custom(token.preferredFontName, size: token.size, relativeTo: token.relativeTextStyle)
        }
        return .system(size: token.size, weight: token.fallbackWeight, design: .serif)
    }

    private func subtitleFont() -> Font {
        if UIFont(name: "PlayfairDisplay-Regular", size: 16) != nil {
            return Font.custom("PlayfairDisplay-Regular", size: 16)
        }
        return .system(size: 16, design: .serif)
    }

    private func upNextTitleFont() -> Font {
        if UIFont(name: "PlayfairDisplay-Medium", size: 14) != nil {
            return Font.custom("PlayfairDisplay-Medium", size: 14)
        }
        return .system(size: 14, weight: .medium, design: .serif)
    }

    private func upNextSubtitleFont() -> Font {
        if UIFont(name: "PlayfairDisplay-Regular", size: 12) != nil {
            return Font.custom("PlayfairDisplay-Regular", size: 12)
        }
        return .system(size: 12, design: .serif)
    }

    private func sectionFont() -> Font {
        let token = LunaraVisualTokens.headingToken(for: .section, weight: .semibold)
        if UIFont(name: token.preferredFontName, size: token.size) != nil {
            return .custom(token.preferredFontName, size: token.size, relativeTo: token.relativeTextStyle)
        }
        return .system(size: token.size, weight: token.fallbackWeight, design: .serif)
    }
}

// MARK: - Seek Bar (isolated observation scope)

/// Separate View struct so that elapsed/duration polling only re-renders
/// the seek bar — not the artwork, track info, or up-next list.
private struct NowPlayingSeekBar: View {
    let viewModel: NowPlayingScreenViewModel

    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isSeeking ? seekTime : viewModel.elapsed },
                    set: { newValue in
                        isSeeking = true
                        seekTime = newValue
                    }
                ),
                in: 0...max(viewModel.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        viewModel.commitSeek(to: seekTime)
                        isSeeking = false
                    }
                }
            )
            .tint(viewModel.palette.accent)

            HStack {
                Text(formatTime(isSeeking ? seekTime : viewModel.elapsed))
                    .font(timestampFont())
                    .foregroundStyle(viewModel.palette.textSecondary)
                Spacer()
                Text(formatCountdown(elapsed: isSeeking ? seekTime : viewModel.elapsed, duration: viewModel.duration))
                    .font(timestampFont())
                    .foregroundStyle(viewModel.palette.textSecondary)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(0, time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatCountdown(elapsed: TimeInterval, duration: TimeInterval) -> String {
        let remaining = Int(max(0, duration - elapsed))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "-%d:%02d", minutes, seconds)
    }

    private func timestampFont() -> Font {
        if UIFont(name: "PlayfairDisplay-Regular", size: 12) != nil {
            return Font.custom("PlayfairDisplay-Regular", size: 12)
        }
        return .system(size: 12, design: .serif)
    }
}
