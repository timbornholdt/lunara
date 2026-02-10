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

    var body: some View {
        if authViewModel.isAuthenticated {
            MainTabView(
                libraryViewModel: LibraryViewModel(sessionInvalidationHandler: { authViewModel.signOut() }),
                collectionsViewModel: CollectionsViewModel(sessionInvalidationHandler: { authViewModel.signOut() }),
                playbackViewModel: playbackViewModel
            ) {
                playbackViewModel.stop()
                authViewModel.signOut()
            }
        } else {
            SignInView(viewModel: authViewModel)
        }
    }
}

private struct MainTabView: View {
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var collectionsViewModel: CollectionsViewModel
    @ObservedObject var playbackViewModel: PlaybackViewModel
    let signOut: () -> Void

    init(
        libraryViewModel: LibraryViewModel,
        collectionsViewModel: CollectionsViewModel,
        playbackViewModel: PlaybackViewModel,
        signOut: @escaping () -> Void
    ) {
        _libraryViewModel = StateObject(wrappedValue: libraryViewModel)
        _collectionsViewModel = StateObject(wrappedValue: collectionsViewModel)
        self.playbackViewModel = playbackViewModel
        self.signOut = signOut
    }

    var body: some View {
        TabView {
            LibraryBrowseView(
                viewModel: libraryViewModel,
                playbackViewModel: playbackViewModel,
                signOut: signOut
            )
            .tabItem {
                Label("All Albums", systemImage: "square.grid.2x2")
            }

            CollectionsBrowseView(
                viewModel: collectionsViewModel,
                playbackViewModel: playbackViewModel,
                signOut: signOut
            )
            .tabItem {
                Label("Collections", systemImage: "rectangle.stack")
            }
        }
    }
}

#Preview {
    ContentView()
}
