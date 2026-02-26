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
    @State private var selectedAlbumFromNowPlaying: Album?
    @State private var selectedArtistFromNowPlaying: Artist?
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
                            offlineStore: coordinator.offlineStore
                        )
                    )
                    .toolbarBackground(Color(red: 0.12, green: 0.13, blue: 0.04), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                    .toolbarColorScheme(.dark, for: .tabBar)
                }

                Tab("Albums", systemImage: "square.grid.2x2", value: TabID.albums) {
                    LibraryGridView(
                        viewModel: LibraryGridViewModel(
                            library: coordinator.libraryRepo,
                            artworkPipeline: coordinator.artworkPipeline,
                            actions: coordinator,
                            downloadManager: coordinator.downloadManager
                        ),
                        backgroundRefreshSuccessToken: coordinator.backgroundRefreshSuccessToken,
                        backgroundRefreshFailureToken: coordinator.backgroundRefreshFailureToken,
                        backgroundRefreshErrorMessage: coordinator.lastBackgroundRefreshErrorMessage,
                        externalSelectedAlbum: $selectedAlbumFromNowPlaying
                    )
                    .toolbarBackground(Color(red: 0.12, green: 0.13, blue: 0.04), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                    .toolbarColorScheme(.dark, for: .tabBar)
                }

                Tab("Artists", systemImage: "music.mic", value: TabID.artists) {
                    ArtistsListView(
                        viewModel: ArtistsListViewModel(
                            library: coordinator.libraryRepo,
                            artworkPipeline: coordinator.artworkPipeline,
                            actions: coordinator,
                            downloadManager: coordinator.downloadManager
                        ),
                        externalSelectedArtist: $selectedArtistFromNowPlaying
                    )
                    .toolbarBackground(Color(red: 0.12, green: 0.13, blue: 0.04), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                    .toolbarColorScheme(.dark, for: .tabBar)
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
                    .toolbarBackground(Color(red: 0.12, green: 0.13, blue: 0.04), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                    .toolbarColorScheme(.dark, for: .tabBar)
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
                        selectedTab = .albums
                        selectedAlbumFromNowPlaying = album
                    },
                    onNavigateToArtist: { artist in
                        selectedTab = .artists
                        selectedArtistFromNowPlaying = artist
                    }
                )
                .padding(.bottom, 56)
            }
        }
    }

}

#Preview {
    LibraryRootTabView(coordinator: AppCoordinator())
}
