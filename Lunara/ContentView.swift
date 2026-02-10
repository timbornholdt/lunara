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
                MainTabView(
                    libraryViewModel: LibraryViewModel(sessionInvalidationHandler: { authViewModel.signOut() }),
                    collectionsViewModel: CollectionsViewModel(sessionInvalidationHandler: { authViewModel.signOut() }),
                    artistsViewModel: ArtistsViewModel(sessionInvalidationHandler: { authViewModel.signOut() }),
                    playbackViewModel: playbackViewModel
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
    @State private var selectedTab: Tab = .library
    @State private var showNowPlaying = false
    @State private var libraryPath = NavigationPath()
    @State private var collectionsPath = NavigationPath()
    @State private var artistsPath = NavigationPath()
    @State private var hadNowPlaying = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        libraryViewModel: LibraryViewModel,
        collectionsViewModel: CollectionsViewModel,
        artistsViewModel: ArtistsViewModel,
        playbackViewModel: PlaybackViewModel,
        signOut: @escaping () -> Void
    ) {
        _libraryViewModel = StateObject(wrappedValue: libraryViewModel)
        _collectionsViewModel = StateObject(wrappedValue: collectionsViewModel)
        _artistsViewModel = StateObject(wrappedValue: artistsViewModel)
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
                navigationPath: $artistsPath
            )
            .tabItem {
                Label("Artists", systemImage: "person.2")
            }
            .tag(Tab.artists)
        }
        .safeAreaInset(edge: .bottom) {
            if let nowPlaying = playbackViewModel.nowPlaying {
                NowPlayingBarView(
                    state: nowPlaying,
                    palette: palette,
                    onTogglePlayPause: { playbackViewModel.togglePlayPause() },
                    onOpenNowPlaying: { showNowPlaying = true }
                )
                .padding(.horizontal, LunaraTheme.Layout.globalPadding)
                .padding(.bottom, tabBarHeight + 8)
                .opacity(showNowPlaying ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: showNowPlaying)
                .allowsHitTesting(!showNowPlaying)
            }
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
        .onChange(of: playbackViewModel.nowPlaying?.trackRatingKey) { _, newValue in
            let isPlayingNow = newValue != nil
            if isPlayingNow && !hadNowPlaying {
                showNowPlaying = true
            }
            hadNowPlaying = isPlayingNow
        }
    }

    private enum Tab {
        case collections
        case library
        case artists
    }

}

#Preview {
    ContentView()
}
