import SwiftUI
import os

/// Debug view for Phase 1 verification
/// Shows basic album fetching to verify Plex connectivity
/// Will be replaced with proper UI in Phase 4
struct DebugLibraryView: View {

    let coordinator: AppCoordinator
    private let logger = Logger(subsystem: "holdings.chinlock.lunara", category: "DebugLibraryView")
    private let duplicateReporter = AlbumDuplicateDebugReporter()

    @State private var albums: [Album] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
            .navigationTitle("Debug Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Fetch Albums") {
                        refreshAlbumsUserInitiated()
                    }
                    .disabled(isLoading)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign Out") {
                        coordinator.signOut()
                    }
                }
            }
            .task {
                // Auto-fetch albums on first appearance
                if albums.isEmpty && !isLoading {
                    fetchAlbumsOnLaunch()
                }
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
        coordinator.queueManager.currentItem?.trackID ?? "none"
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

    // MARK: - Actions

    private func fetchAlbumsOnLaunch() {
        loadAlbums(
            logMessage: "Fetch albums requested for app launch from debug screen",
            loader: { try await coordinator.loadLibraryOnLaunch() }
        )
    }

    private func refreshAlbumsUserInitiated() {
        loadAlbums(
            logMessage: "Fetch albums requested from debug screen",
            loader: { try await coordinator.fetchAlbums() }
        )
    }

    private func loadAlbums(
        logMessage: String,
        loader: @escaping @MainActor () async throws -> [Album]
    ) {
        logger.info("\(logMessage, privacy: .public)")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedAlbums = try await loader()
                await MainActor.run {
                    self.albums = fetchedAlbums
                    self.isLoading = false
                }
                logger.info("Fetched \(fetchedAlbums.count, privacy: .public) albums")
                duplicateReporter.logReport(
                    albums: fetchedAlbums,
                    logger: logger,
                    spotlightTitle: "After the Gold Rush",
                    spotlightArtist: "Neil Young"
                )
            } catch let error as LibraryError {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.userMessage
                }
                logger.error("Fetch albums failed with LibraryError: \(String(describing: error), privacy: .public)")
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
                logger.error("Fetch albums failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func playAlbum(_ album: Album) {
        logger.info("Play tapped for album '\(album.title, privacy: .public)' with plexID '\(album.plexID, privacy: .public)'")
        Task {
            do {
                try await coordinator.playAlbum(album)
                logger.info("Play request succeeded for album '\(album.title, privacy: .public)'")
            } catch let error as LunaraError {
                await MainActor.run {
                    self.errorMessage = error.userMessage
                }
                logger.error("Play request failed for album '\(album.title, privacy: .public)'. Error: \(String(describing: error), privacy: .public)")
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
                logger.error("Play request failed for album '\(album.title, privacy: .public)' with unexpected error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DebugLibraryView(coordinator: AppCoordinator())
}
