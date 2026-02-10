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
