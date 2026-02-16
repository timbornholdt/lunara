import SwiftUI

/// Debug view for Phase 1 verification
/// Shows basic album fetching to verify Plex connectivity
/// Will be replaced with proper UI in Phase 4
struct DebugLibraryView: View {

    let coordinator: AppCoordinator

    @State private var albums: [Album] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
                        fetchAlbums()
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
                    fetchAlbums()
                }
            }
        }
    }

    // MARK: - Subviews

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
            }
        }
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
                fetchAlbums()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func fetchAlbums() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedAlbums = try await coordinator.plexClient.fetchAlbums()
                await MainActor.run {
                    self.albums = fetchedAlbums
                    self.isLoading = false
                }
            } catch let error as LibraryError {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.userMessage
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DebugLibraryView(coordinator: AppCoordinator())
}
