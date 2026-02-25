import SwiftUI
import UIKit

/// Floating compact strip shown above the tab bar when something is queued.
/// Tapping opens NowPlayingStubSheet. Hides itself when the queue is empty.
struct NowPlayingBar: View {
    let viewModel: NowPlayingBarViewModel
    let screenViewModel: NowPlayingScreenViewModel
    @Binding var showSheet: Bool
    var onNavigateToAlbum: ((Album) -> Void)?
    var onNavigateToArtist: ((Artist) -> Void)?

    var body: some View {
        if viewModel.isVisible {
            barContent
                .background(screenViewModel.palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 12)
                .onTapGesture {
                    showSheet = true
                }
                .sheet(isPresented: $showSheet) {
                    NowPlayingScreen(
                        viewModel: screenViewModel,
                        onNavigateToAlbum: { album in
                            showSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onNavigateToAlbum?(album)
                            }
                        },
                        onNavigateToArtist: { artist in
                            showSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onNavigateToArtist?(artist)
                            }
                        }
                    )
                }
                .animation(.easeInOut(duration: 0.4), value: screenViewModel.palette)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isVisible)
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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        artworkPlaceholder
                    }
                }
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
