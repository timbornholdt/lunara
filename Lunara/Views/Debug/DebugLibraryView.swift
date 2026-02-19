import SwiftUI
import os

/// Debug view for Phase 1 verification
/// Shows basic album fetching to verify Plex connectivity
/// Will be replaced with proper UI in Phase 4
struct DebugLibraryView: View {
    let coordinator: AppCoordinator
    let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "DebugLibraryView")
    let duplicateReporter = AlbumDuplicateDebugReporter()

    @State var albums: [Album] = []
    @State var isLoading = false
    @State var errorMessage: String?
    @State var errorBannerState = ErrorBannerState()
    @State var tracksByID: [String: Track] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                LunaraStylePrimitivesShowcase()

                playbackPanel

                if isLoading {
                    ProgressView("Fetching albums...")
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if albums.isEmpty {
                    emptyView
                } else {
                    albumList
                }
            }
            .lunaraLinenBackground()
            .navigationTitle("Debug Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Fetch Albums") {
                        refreshAlbumsUserInitiated()
                    }
                    .disabled(isLoading)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Test Banner") {
                        showTestBanner()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign Out") {
                        coordinator.signOut()
                    }
                }
            }
            .lunaraErrorBanner(using: errorBannerState)
            .task {
                // Auto-fetch albums on first appearance
                if albums.isEmpty && !isLoading {
                    fetchAlbumsOnLaunch()
                }
            }
            .task(id: coordinator.backgroundRefreshSuccessToken) {
                await applyBackgroundRefreshIfNeeded()
            }
            .task(id: coordinator.backgroundRefreshFailureToken) {
                applyBackgroundRefreshFailureIfNeeded()
            }
        }
    }

    // MARK: - Subviews

    private var playbackPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback Debug")
                .font(.headline)

            HStack {
                Text("State")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(playbackStateLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(playbackStateColor)
            }

            HStack {
                Text("Current Track")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentTrackLabel)
                    .font(.caption.monospaced())
            }

            HStack(spacing: 8) {
                Button("Pause") {
                    coordinator.pausePlayback()
                }
                .buttonStyle(.bordered)

                Button("Resume") {
                    coordinator.resumePlayback()
                }
                .buttonStyle(.bordered)

                Button("Skip") {
                    coordinator.skipToNextTrack()
                }
                .buttonStyle(.bordered)

                Button("Stop") {
                    coordinator.stopPlayback()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Tap 'Fetch Albums' to load your library")
                .foregroundStyle(.secondary)
        }
    }

    private var albumList: some View {
        List {
            Section {
                Text("Found \(albums.count) albums")
                    .font(.headline)
            }

            ForEach(albums) { album in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.title)
                            .font(.headline)
                        Text(album.artistName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let year = album.year {
                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Button("Play") {
                        playAlbum(album)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var playbackStateLabel: String {
        switch coordinator.playbackEngine.playbackState {
        case .idle:
            return "Idle"
        case .buffering:
            return "Buffering"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    private var playbackStateColor: Color {
        switch coordinator.playbackEngine.playbackState {
        case .idle:
            return .secondary
        case .buffering:
            return .orange
        case .playing:
            return .green
        case .paused:
            return .yellow
        case .error:
            return .red
        }
    }

    private var currentTrackLabel: String {
        DebugCurrentTrackFormatter.label(for: coordinator.queueManager.currentItem?.trackID, tracksByID: tracksByID)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                refreshAlbumsUserInitiated()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

}

// MARK: - Preview

#Preview {
    DebugLibraryView(coordinator: AppCoordinator())
}
