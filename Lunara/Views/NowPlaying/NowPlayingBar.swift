import SwiftUI
import UIKit

/// Compact strip in the tab view's bottom accessory slot when something is
/// queued. Tapping opens the Now Playing sheet. Hides when the queue is empty.
/// The accessory capsule supplies shape, margins, and clipping — the bar only
/// paints its palette color (Lunara-c5q).
struct NowPlayingBar: View {
    let viewModel: NowPlayingBarViewModel
    let screenViewModel: NowPlayingScreenViewModel
    @Binding var showSheet: Bool

    var body: some View {
        // No .sheet here: the accessory tears its content down on visibility
        // changes, and a sheet hosted inside it gets auto-dismissed
        // mid-presentation (Lunara-m73). LibraryRootTabView hosts the sheet.
        if viewModel.isVisible {
            barContent
                .background(screenViewModel.palette.background)
                .onTapGesture {
                    showSheet = true
                }
                .animation(.easeInOut(duration: 0.4), value: screenViewModel.palette)
        }
    }

    // MARK: - Bar Layout

    private var barContent: some View {
        HStack(spacing: 12) {
            artworkView
            trackInfo
            Spacer(minLength: 0)
            playPauseButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let url = viewModel.artworkFileURL {
                // Cached decode renders on the first frame — AsyncImage
                // restarted from scratch on every bar rebuild, flickering the
                // art during playback startup (Lunara-m73).
                DownsampledThumbnail(url: url, maxPixelSize: 132)
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(screenViewModel.palette.textSecondary.opacity(0.3))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 18))
                    .foregroundStyle(screenViewModel.palette.textSecondary)
            }
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.trackTitle ?? "")
                .font(playfairFont(size: 14))
                .foregroundStyle(screenViewModel.palette.textPrimary)
                .lineLimit(1)
                .accessibilityLabel("Now playing: \(viewModel.trackTitle ?? "unknown")")

            if let artist = viewModel.artistName {
                Text(artist)
                    .font(playfairFont(size: 12))
                    .foregroundStyle(screenViewModel.palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Play / Pause Button

    @ViewBuilder
    private var playPauseButton: some View {
        switch viewModel.playbackState {
        case .buffering, .playing:
            barButton(systemImage: "pause.fill", label: "Pause") {
                viewModel.togglePlayPause()
            }

        case .paused:
            barButton(systemImage: "play.fill", label: "Play") {
                viewModel.togglePlayPause()
            }

        case .idle:
            barButton(systemImage: "play.fill", label: "Play") {
                viewModel.togglePlayPause()
            }

        case .error:
            barButton(systemImage: "exclamationmark.circle", label: "Playback error") {
                // Error state: tapping the bar opens the sheet where error context will live.
            }
        }
    }

    private func barButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(screenViewModel.palette.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    screenViewModel.palette.textPrimary.opacity(0.15),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Typography

    private func playfairFont(size: CGFloat) -> Font {
        if let _ = UIFont(name: "PlayfairDisplay-Regular", size: size) {
            return Font.custom("PlayfairDisplay-Regular", size: size)
        }
        return .system(size: size, design: .serif)
    }
}
