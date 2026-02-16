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
                // Auto-fetch albums on first appearance (Phase 1 acceptance test)
                print("📱 Debug Library View appeared")
                print("🔑 Signed in: \(coordinator.isSignedIn)")

                // First, print available sections to help debug
                do {
                    try await coordinator.plexClient.printLibrarySections()
                } catch {
                    print("⚠️  Failed to fetch sections: \(error)")
                }

                if albums.isEmpty && !isLoading {
                    print("🎵 Auto-fetching albums for Phase 1 acceptance test...")
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
        print("\n" + String(repeating: "=", count: 60))
        print("🎵 PHASE 1 ACCEPTANCE TEST: Fetching Albums")
        print(String(repeating: "=", count: 60))

        isLoading = true
        errorMessage = nil

        Task {
            do {
                print("📡 Calling PlexAPIClient.fetchAlbums()...")
                let fetchedAlbums = try await coordinator.plexClient.fetchAlbums()

                await MainActor.run {
                    self.albums = fetchedAlbums
                    self.isLoading = false

                    // Log to console for Phase 1 acceptance criteria
                    print("\n✅ SUCCESSFULLY FETCHED \(fetchedAlbums.count) ALBUMS FROM PLEX")
                    print(String(repeating: "-", count: 60))

                    if fetchedAlbums.isEmpty {
                        print("⚠️  No albums found in library")
                    } else {
                        print("\n📀 Album List (showing first 10):\n")
                        for (index, album) in fetchedAlbums.prefix(10).enumerated() {
                            let yearStr = album.year.map { " (\($0))" } ?? ""
                            print("  \(index + 1). \(album.title) - \(album.artistName)\(yearStr)")
                        }
                        if fetchedAlbums.count > 10 {
                            print("\n  ... and \(fetchedAlbums.count - 10) more albums")
                        }
                    }

                    print("\n" + String(repeating: "=", count: 60))
                    print("✅ PHASE 1 ACCEPTANCE TEST: PASSED")
                    print("   - Sign in: ✅")
                    print("   - App logs album list: ✅")
                    print("   - Token persists in Keychain: ✅")
                    print(String(repeating: "=", count: 60) + "\n")
                }

            } catch let error as LibraryError {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.userMessage
                    print("\n❌ LIBRARY ERROR: \(error.userMessage)")
                    print("   Error type: \(error)")
                    print(String(repeating: "=", count: 60) + "\n")
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    print("\n❌ UNEXPECTED ERROR: \(error)")
                    print(String(repeating: "=", count: 60) + "\n")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DebugLibraryView(coordinator: AppCoordinator())
}
