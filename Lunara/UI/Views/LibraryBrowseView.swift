import SwiftUI

struct LibraryBrowseView: View {
    @StateObject var viewModel: LibraryViewModel
    let signOut: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.sections.count > 1 {
                    Picker("Library", selection: Binding(
                        get: { viewModel.selectedSection?.key ?? "" },
                        set: { newValue in
                            if let section = viewModel.sections.first(where: { $0.key == newValue }) {
                                Task { await viewModel.selectSection(section) }
                            }
                        }
                    )) {
                        ForEach(viewModel.sections, id: \.key) { section in
                            Text(section.title).tag(section.key)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                if viewModel.isLoading {
                    ProgressView("Loading library...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.albums, id: \.ratingKey) { album in
                                NavigationLink {
                                    AlbumDetailView(album: album, sessionInvalidationHandler: signOut)
                                } label: {
                                    AlbumCardView(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                Button("Sign Out") {
                    signOut()
                }
            }
        }
        .task {
            await viewModel.loadSections()
        }
    }
}

private struct AlbumCardView: View {
    let album: PlexAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumArtworkView(album: album)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(album.title)
                .font(.headline)
                .lineLimit(2)

            if let year = album.year {
                Text(String(year))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AlbumArtworkView: View {
    let album: PlexAlbum

    var body: some View {
        if let url = artworkURL() {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color.gray.opacity(0.2)
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Color.gray.opacity(0.2)
                        .overlay(Text("No Art").font(.caption))
                @unknown default:
                    Color.gray.opacity(0.2)
                }
            }
        } else {
            Color.gray.opacity(0.2)
                .overlay(Text("No Art").font(.caption))
        }
    }

    private func artworkURL() -> URL? {
        guard let serverURL = UserDefaults.standard.string(forKey: "plex.server.baseURL"),
              let baseURL = URL(string: serverURL) else {
            return nil
        }
        let storedToken = try? PlexAuthTokenStore(keychain: KeychainStore()).load()
        guard let token = storedToken ?? nil else {
            return nil
        }
        let builder = PlexArtworkURLBuilder(baseURL: baseURL, token: token, maxSize: PlexDefaults.maxArtworkSize)
        let resolver = AlbumArtworkResolver(artworkBuilder: builder)
        return resolver.artworkURL(for: album)
    }
}
