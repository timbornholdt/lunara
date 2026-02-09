//
//  ContentView.swift
//  Lunara
//
//  Created by Tim Bornholdt on 2/8/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        if authViewModel.isAuthenticated {
            LibraryBrowseView(viewModel: LibraryViewModel(sessionInvalidationHandler: { authViewModel.signOut() })) {
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
