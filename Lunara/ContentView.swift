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
            LibraryBrowseView(
                viewModel: LibraryViewModel(sessionInvalidationHandler: { authViewModel.signOut() }),
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

#Preview {
    ContentView()
}
