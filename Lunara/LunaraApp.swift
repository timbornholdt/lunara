//
//  LunaraApp.swift
//  Lunara
//
//  Created by Tim Bornholdt on 2/16/26.
//

import SwiftUI

@main
struct LunaraApp: App {

    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            Group {
                if coordinator.isSignedIn {
                    DebugLibraryView(coordinator: coordinator)
                } else {
                    SignInView(coordinator: coordinator)
                }
            }
        }
    }
}
