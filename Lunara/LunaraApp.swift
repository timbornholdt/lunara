//
//  LunaraApp.swift
//  Lunara
//
//  Created by Tim Bornholdt on 2/8/26.
//

import SwiftUI

extension Notification.Name {
    static let lunaraScenePhaseDidChange = Notification.Name("lunaraScenePhaseDidChange")
}

@main
struct LunaraApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            NotificationCenter.default.post(
                name: .lunaraScenePhaseDidChange,
                object: nil,
                userInfo: ["phase": "\(newPhase)"]
            )
        }
    }
}
