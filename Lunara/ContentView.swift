//
//  ContentView.swift
//  Lunara
//
//  Created by Tim Bornholdt on 2/8/26.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var playbackViewModel = PlaybackViewModel()
    @State private var showInitialScreen = true

    var body: some View {
        ZStack {
            switch authViewModel.launchState {
            case .authenticated:
                let settingsStore = UserDefaultsAppSettingsStore()
                MainTabView(
                    libraryViewModel: LibraryViewModel(
                        settingsStore: settingsStore,
                        sessionInvalidationHandler: { authViewModel.signOut() }
                    ),
                    collectionsViewModel: CollectionsViewModel(sessionInvalidationHandler: { authViewModel.signOut() }),
                    artistsViewModel: ArtistsViewModel(sessionInvalidationHandler: { authViewModel.signOut() }),
                    playbackViewModel: playbackViewModel,
                    settingsStore: settingsStore
                ) {
                    playbackViewModel.stop()
                    authViewModel.signOut()
                }
            case .unauthenticated:
                SignInView(viewModel: authViewModel)
            case .checking:
                Color.clear
            }
        }
        .overlay {
            if showInitialScreen {
                InitialScreenView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            DiagnosticsLogger.shared.log(.appLaunch)
            showInitialScreen = !authViewModel.didFinishInitialTokenCheck
        }
        .onChange(of: authViewModel.didFinishInitialTokenCheck) { _, finished in
            guard finished else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showInitialScreen = false
            }
        }
    }
}

private struct MainTabView: View {
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var collectionsViewModel: CollectionsViewModel
    @StateObject private var artistsViewModel: ArtistsViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void
    @State private var selectedTab: Tab = .collections
    @State private var showNowPlaying = false
    @State private var libraryPath = NavigationPath()
    @State private var collectionsPath = NavigationPath()
    @State private var artistsPath = NavigationPath()
    @State private var hadNowPlaying = false
    @State private var nowPlayingInsetHeight: CGFloat = 0
    @State private var showSettings = false
    @StateObject private var settingsViewModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(
        libraryViewModel: LibraryViewModel,
        collectionsViewModel: CollectionsViewModel,
        artistsViewModel: ArtistsViewModel,
        playbackViewModel: PlaybackViewModel,
        settingsStore: AppSettingsStoring = UserDefaultsAppSettingsStore(),
        signOut: @escaping () -> Void
    ) {
        _libraryViewModel = StateObject(wrappedValue: libraryViewModel)
        _collectionsViewModel = StateObject(wrappedValue: collectionsViewModel)
        _artistsViewModel = StateObject(wrappedValue: artistsViewModel)
        _settingsViewModel = StateObject(
            wrappedValue: SettingsViewModel(
                settingsStore: settingsStore,
                onSignOut: signOut
            )
        )
        self.playbackViewModel = playbackViewModel
        self.signOut = signOut
    }

    var body: some View {
        let palette = LunaraTheme.Palette.colors(for: colorScheme)
        let basePalette = ThemePalette(palette: palette)
        let themePalette = playbackViewModel.albumTheme.map(ThemePalette.init(theme:)) ?? basePalette
        let tabBarHeight: CGFloat = 49

        TabView(selection: $selectedTab) {
            CollectionsBrowseView(
                viewModel: collectionsViewModel,
                playbackViewModel: playbackViewModel,
                signOut: signOut,
                openSettings: { showSettings = true },
                navigationPath: $collectionsPath
            )
            .tabItem {
                Label("Collections", systemImage: "rectangle.stack")
            }
            .tag(Tab.collections)

            LibraryBrowseView(
                viewModel: libraryViewModel,
                playbackViewModel: playbackViewModel,
                signOut: signOut,
                openSettings: { showSettings = true },
                navigationPath: $libraryPath
            )
            .tabItem {
                Label("Albums", systemImage: "square.grid.2x2")
            }
            .tag(Tab.library)

            ArtistsBrowseView(
                viewModel: artistsViewModel,
                playbackViewModel: playbackViewModel,
                signOut: signOut,
                openSettings: { showSettings = true },
                navigationPath: $artistsPath
            )
            .tabItem {
                Label("Artists", systemImage: "person.2")
            }
            .tag(Tab.artists)
        }
        .environment(\.nowPlayingInsetHeight, nowPlayingInsetHeight)
        .safeAreaInset(edge: .bottom) {
            if let nowPlaying = playbackViewModel.nowPlaying {
                NowPlayingBarView(
                    state: nowPlaying,
                    palette: palette,
                    onTogglePlayPause: { playbackViewModel.togglePlayPause() },
                    onOpenNowPlaying: { showNowPlaying = true }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: NowPlayingInsetHeightKey.self, value: proxy.size.height)
                    }
                )
                .padding(.horizontal, LunaraTheme.Layout.globalPadding)
                .padding(.bottom, tabBarHeight + 8)
                .opacity(showNowPlaying ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: showNowPlaying)
                .allowsHitTesting(!showNowPlaying)
            }
        }
        .onPreferenceChange(NowPlayingInsetHeightKey.self) { height in
            nowPlayingInsetHeight = height > 0 ? height + tabBarHeight + 8 : 0
        }
        .sheet(isPresented: $showNowPlaying) {
            if let nowPlaying = playbackViewModel.nowPlaying {
                NowPlayingSheetView(
                    state: nowPlaying,
                    context: playbackViewModel.nowPlayingContext,
                    palette: themePalette,
                    theme: playbackViewModel.albumTheme,
                    onTogglePlayPause: { playbackViewModel.togglePlayPause() },
                    onNext: { playbackViewModel.skipToNext() },
                    onPrevious: { playbackViewModel.skipToPrevious() },
                    onSeek: { playbackViewModel.seek(to: $0) },
                    onSelectTrack: { track in
                        guard let context = playbackViewModel.nowPlayingContext,
                              let index = context.tracks.firstIndex(where: { $0.ratingKey == track.ratingKey }) else {
                            return
                        }
                        playbackViewModel.play(tracks: context.tracks, startIndex: index, context: context)
                    },
                    onClearQueue: {
                        playbackViewModel.clearUpcomingQueue()
                    },
                    onRemoveUpNextAtIndex: { index in
                        playbackViewModel.removeUpcomingQueueItem(atAbsoluteIndex: index)
                    },
                    onNavigateToAlbum: {
                        guard let context = playbackViewModel.nowPlayingContext else { return }
                        let request = AlbumNavigationRequest(
                            album: context.album,
                            albumRatingKeys: context.albumRatingKeys
                        )
                        switch selectedTab {
                        case .library:
                            libraryPath.append(request)
                        case .collections:
                            collectionsPath.append(request)
                        case .artists:
                            artistsPath.append(request)
                        }
                        showNowPlaying = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                viewModel: settingsViewModel,
                playbackViewModel: playbackViewModel,
                signOut: signOut
            )
        }
        .onChange(of: playbackViewModel.nowPlaying?.trackRatingKey) { _, newValue in
            let isPlayingNow = newValue != nil
            if isPlayingNow && !hadNowPlaying {
                showNowPlaying = true
            }
            hadNowPlaying = isPlayingNow
            if !isPlayingNow {
                nowPlayingInsetHeight = 0
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            let tabName: String
            switch newTab {
            case .collections: tabName = "collections"
            case .library: tabName = "library"
            case .artists: tabName = "artists"
            }
            DiagnosticsLogger.shared.log(.navigationTabChange(tab: tabName))
        }
        .onChange(of: collectionsPath) { _, _ in
            DiagnosticsLogger.shared.log(.navigationScreenPush(screenType: "collections", key: "browse"))
        }
        .onChange(of: libraryPath) { _, _ in
            DiagnosticsLogger.shared.log(.navigationScreenPush(screenType: "library", key: "browse"))
        }
        .onChange(of: artistsPath) { _, _ in
            DiagnosticsLogger.shared.log(.navigationScreenPush(screenType: "artists", key: "browse"))
        }
    }

    private enum Tab {
        case collections
        case library
        case artists
    }

}

private struct NowPlayingInsetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NowPlayingInsetHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var nowPlayingInsetHeight: CGFloat {
        get { self[NowPlayingInsetHeightEnvironmentKey.self] }
        set { self[NowPlayingInsetHeightEnvironmentKey.self] = newValue }
    }
}

#Preview {
    ContentView()
}
