import SwiftUI
import UIKit

struct LibraryRootTabView: View {
    private enum Tab: Hashable {
        case collections
        case albums
        case artists
    }

    let coordinator: AppCoordinator
    let tabBarTheme: LunaraTabBarTheme

    @State private var selectedTab: Tab = .collections
    @State private var selectedAlbumFromNowPlaying: Album?
    @State private var nowPlayingBarViewModel: NowPlayingBarViewModel
    @State private var nowPlayingScreenViewModel: NowPlayingScreenViewModel

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
                CollectionsListView(
                    viewModel: CollectionsListViewModel(
                        library: coordinator.libraryRepo,
                        artworkPipeline: coordinator.artworkPipeline,
                        actions: coordinator
                    )
                )
                .tabItem {
                    Label("Collections", systemImage: "rectangle.stack")
                }
                .tag(Tab.collections)

                LibraryGridView(
                    viewModel: LibraryGridViewModel(
                        library: coordinator.libraryRepo,
                        artworkPipeline: coordinator.artworkPipeline,
                        actions: coordinator
                    ),
                    backgroundRefreshSuccessToken: coordinator.backgroundRefreshSuccessToken,
                    backgroundRefreshFailureToken: coordinator.backgroundRefreshFailureToken,
                    backgroundRefreshErrorMessage: coordinator.lastBackgroundRefreshErrorMessage,
                    externalSelectedAlbum: $selectedAlbumFromNowPlaying
                )
                .tabItem {
                    Label("Albums", systemImage: "square.grid.2x2")
                }
                .tag(Tab.albums)

                artistsPlaceholder
                    .tabItem {
                        Label("Artists", systemImage: "music.mic")
                    }
                    .tag(Tab.artists)
            }
            .tint(Color.lunara(tabBarTheme.selectedTintRole))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingBar(
                    viewModel: nowPlayingBarViewModel,
                    screenViewModel: nowPlayingScreenViewModel,
                    onNavigateToAlbum: { album in
                        selectedTab = .albums
                        selectedAlbumFromNowPlaying = album
                    }
                )
            }
        }
    }

    private var artistsPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.mic")
                .font(.system(size: 48))
                .foregroundStyle(Color.lunara(.textSecondary))
            Text("Artists coming soon")
                .foregroundStyle(Color.lunara(.textSecondary))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lunaraLinenBackground()
    }
}

#Preview {
    LibraryRootTabView(coordinator: AppCoordinator())
}
