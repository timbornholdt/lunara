import SwiftUI
import UIKit

struct LibraryRootTabView: View {
    private enum TabID: Hashable {
        case collections
        case albums
        case artists
        case settings
    }

    let coordinator: AppCoordinator
    let tabBarTheme: LunaraTabBarTheme

    @State private var selectedTab: TabID = .collections
    @State private var albumFromNowPlaying: Album?
    @State private var artistFromNowPlaying: Artist?
    @State private var nowPlayingBarViewModel: NowPlayingBarViewModel
    @State private var nowPlayingScreenViewModel: NowPlayingScreenViewModel
    @State private var showNowPlayingSheet = false

    init(coordinator: AppCoordinator, tabBarTheme: LunaraTabBarTheme = .garden) {
        self.coordinator = coordinator
        self.tabBarTheme = tabBarTheme
        self.nowPlayingBarViewModel = NowPlayingBarViewModel(
            queueManager: coordinator.queueManager,
            engine: coordinator.playbackEngine,
            library: coordinator.libraryRepo,
            artworkPipeline: coordinator.artworkPipeline
        )
        self.nowPlayingScreenViewModel = NowPlayingScreenViewModel(
            queueManager: coordinator.queueManager,
            engine: coordinator.playbackEngine,
            library: coordinator.libraryRepo,
            artworkPipeline: coordinator.artworkPipeline
        )
    }

    var body: some View {
        ZStack {
            // Covers the full screen — including the area around and below the
            // iOS 26 floating tab bar pill, which sits outside the TabView's
            // own SwiftUI layout frame and ignores .background() on the TabView.
            // The Liquid Glass pill picks up the UIWindow background color set below.
            Color.lunara(.backgroundBase)
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                Tab("Collections", systemImage: "rectangle.stack", value: TabID.collections) {
                    CollectionsListView(
                        viewModel: CollectionsListViewModel(
                            library: coordinator.libraryRepo,
                            artworkPipeline: coordinator.artworkPipeline,
                            actions: coordinator,
                            downloadManager: coordinator.downloadManager,
                            gardenClient: coordinator.gardenClient,
                            offlineStore: coordinator.offlineStore
                        )
                    )
                    .toolbarBackground(Color.lunara(.backgroundBase), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                }

                Tab("Albums", systemImage: "square.grid.2x2", value: TabID.albums) {
                    LibraryGridView(
                        viewModel: LibraryGridViewModel(
                            library: coordinator.libraryRepo,
                            artworkPipeline: coordinator.artworkPipeline,
                            actions: coordinator,
                            downloadManager: coordinator.downloadManager,
                            gardenClient: coordinator.gardenClient
                        ),
                        backgroundRefreshSuccessToken: coordinator.backgroundRefreshSuccessToken,
                        backgroundRefreshFailureToken: coordinator.backgroundRefreshFailureToken,
                        backgroundRefreshErrorMessage: coordinator.lastBackgroundRefreshErrorMessage
                    )
                    .toolbarBackground(Color.lunara(.backgroundBase), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                }

                Tab("Artists", systemImage: "music.mic", value: TabID.artists) {
                    ArtistsListView(
                        viewModel: ArtistsListViewModel(
                            library: coordinator.libraryRepo,
                            artworkPipeline: coordinator.artworkPipeline,
                            actions: coordinator,
                            downloadManager: coordinator.downloadManager,
                            gardenClient: coordinator.gardenClient
                        ),
                    )
                    .toolbarBackground(Color.lunara(.backgroundBase), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                }

                Tab("Settings", systemImage: "gearshape", value: TabID.settings) {
                    SettingsView(
                        viewModel: SettingsViewModel(
                            offlineStore: coordinator.offlineStore,
                            downloadManager: coordinator.downloadManager,
                            library: coordinator.libraryRepo,
                            signOutAction: { coordinator.signOut() },
                            lastFMAuthManager: coordinator.lastFMAuthManager,
                            scrobbleManager: coordinator.scrobbleManager
                        )
                    )
                    .toolbarBackground(Color.lunara(.backgroundBase), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                }
            }
            .environment(\.showNowPlaying, $showNowPlayingSheet)
            .tint(Color.lunara(tabBarTheme.selectedTintRole))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingBar(
                    viewModel: nowPlayingBarViewModel,
                    screenViewModel: nowPlayingScreenViewModel,
                    showSheet: $showNowPlayingSheet,
                    onNavigateToAlbum: { album in
                        albumFromNowPlaying = album
                    },
                    onNavigateToArtist: { artist in
                        artistFromNowPlaying = artist
                    }
                )
                .padding(.bottom, 52)
            }
        }
        .sheet(item: $albumFromNowPlaying) { album in
            NavigationStack {
                AlbumDetailView(
                    viewModel: AlbumDetailViewModel(
                        album: album,
                        library: coordinator.libraryRepo,
                        artworkPipeline: coordinator.artworkPipeline,
                        actions: coordinator,
                        downloadManager: coordinator.downloadManager,
                        gardenClient: coordinator.gardenClient,
                        review: album.review,
                        genres: album.genres.isEmpty ? nil : album.genres,
                        styles: album.styles,
                        moods: album.moods
                    )
                )
            }
        }
        .sheet(item: $artistFromNowPlaying) { artist in
            NavigationStack {
                ArtistDetailView(
                    viewModel: ArtistDetailViewModel(
                        artist: artist,
                        library: coordinator.libraryRepo,
                        artworkPipeline: coordinator.artworkPipeline,
                        actions: coordinator,
                        downloadManager: coordinator.downloadManager,
                        gardenClient: coordinator.gardenClient
                    )
                )
            }
        }
    }

}

#Preview {
    LibraryRootTabView(coordinator: AppCoordinator())
}
