import SwiftUI
import UIKit

struct LibraryRootTabView: View {
    private enum TabID: Hashable {
        case collections
        case playlists
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
            resolver: coordinator.nowPlayingResolver
        )
        self.nowPlayingScreenViewModel = NowPlayingScreenViewModel(
            queueManager: coordinator.queueManager,
            engine: coordinator.playbackEngine,
            library: coordinator.libraryRepo,
            resolver: coordinator.nowPlayingResolver
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
                        ),
                        refreshStatus: coordinator.refreshStatus
                    )
                    .toolbarBackground(Color.lunara(.backgroundBase), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                }

                Tab("Playlists", systemImage: "music.note.list", value: TabID.playlists) {
                    PlaylistsListView(
                        viewModel: PlaylistsListViewModel(
                            library: coordinator.libraryRepo,
                            artworkPipeline: coordinator.artworkPipeline,
                            actions: coordinator,
                            gardenClient: coordinator.gardenClient
                        ),
                        refreshStatus: coordinator.refreshStatus
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
                        refreshStatus: coordinator.refreshStatus
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
                        refreshStatus: coordinator.refreshStatus,
                        radarService: coordinator.radarService
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
                            scrobbleManager: coordinator.scrobbleManager,
                            playbackTelemetry: coordinator.playbackTelemetry,
                            artworkPipeline: coordinator.artworkPipeline,
                            albumActions: coordinator,
                            gardenClient: coordinator.gardenClient
                        )
                    )
                    .toolbarBackground(Color.lunara(.backgroundBase), for: .tabBar)
                    .toolbarBackgroundVisibility(.visible, for: .tabBar)
                }
            }
            .environment(\.showNowPlaying, $showNowPlayingSheet)
            .environment(\.lastFMClient, coordinator.lastFMClient)
            .environment(\.musicBrainzClient, coordinator.musicBrainzClient)
            .environment(\.ticketmasterClient, coordinator.ticketmasterClient)
            .tint(Color.lunara(tabBarTheme.selectedTintRole))
            // The mini-player lives in iOS 26's bottom accessory slot so every
            // tab's scroll content gets the inset automatically — a plain
            // safeAreaInset outside the TabView never propagated past the
            // floating tab bar, leaving the bar over the last row (Lunara-c5q).
            .tabViewBottomAccessory {
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
        .task {
            // Single launch-time library sync for all tabs. Returns cached data
            // immediately when present and triggers a refresh that bumps the
            // coordinator's success token, which each tab observes to reload.
            _ = try? await coordinator.loadLibraryOnLaunch()
        }
    }

}

#Preview {
    LibraryRootTabView(coordinator: AppCoordinator())
}
