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
    @Environment(\.scenePhase) private var scenePhase
    // The iOS 26 bottom accessory's hosted content stops receiving touches
    // after a scene background/foreground cycle (taps and buttons both dead).
    // Rebuilding the SwiftUI content via .id() did NOT fix it (#148) — the rot
    // is in the accessory's UIKit host. On every return to .active this flag
    // briefly disables the accessory so UIKit destroys and recreates the host,
    // restoring hit-testing (Lunara-drf attempt 2).
    @State private var accessoryResetInFlight = false

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
                            gardenClient: coordinator.gardenClient,
                            plexCredentialsProvider: { [weak coordinator] in
                                await coordinator?.plexDiagnosticsCredentials()
                            },
                            playbackEngine: coordinator.playbackEngine
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
            // isEnabled drives show/hide: the system draws the glass capsule
            // even when the content view resolves to empty (Lunara-ej0), and
            // conditionally applying the modifier itself crashes (FB/forums
            // thread 790913).
            .tabViewBottomAccessory(
                isEnabled: nowPlayingBarViewModel.isVisible && !accessoryResetInFlight
            ) {
                NowPlayingBar(
                    viewModel: nowPlayingBarViewModel,
                    screenViewModel: nowPlayingScreenViewModel,
                    showSheet: $showNowPlayingSheet
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            accessoryResetInFlight = true
            // Re-enable in a later transaction — flipping back in the same
            // update would coalesce and the host would never tear down.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                accessoryResetInFlight = false
            }
        }
        // Hosted here, NOT inside the accessory content: the accessory tears
        // its subtree down on visibility changes, which auto-dismissed a sheet
        // presented from within it (Lunara-m73).
        .sheet(isPresented: $showNowPlayingSheet) {
            NowPlayingScreen(
                viewModel: nowPlayingScreenViewModel,
                onNavigateToAlbum: { album in
                    showNowPlayingSheet = false
                    albumFromNowPlaying = album
                },
                onNavigateToArtist: { artist in
                    showNowPlayingSheet = false
                    artistFromNowPlaying = artist
                }
            )
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
