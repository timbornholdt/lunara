//
//  LunaraApp.swift
//  Lunara
//
//  Created by Tim Bornholdt on 2/16/26.
//

import SwiftUI
import UIKit

@main
struct LunaraApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var coordinator: AppCoordinator
    @State private var colorSchemeManager = ColorSchemeManager()

    init() {
        let coord = AppCoordinator()
        _coordinator = State(initialValue: coord)
        AppCoordinator.shared = coord

    }

    var body: some Scene {
        WindowGroup {
            Group {
                if coordinator.isSignedIn {
                    LibraryRootTabView(coordinator: coordinator)
                } else {
                    SignInView(coordinator: coordinator)
                }
            }
            .id(colorSchemeManager.refreshToken)
            .environment(colorSchemeManager)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                guard url.scheme == "lunara", url.host == "lastfm-callback" else { return }
                Task {
                    try? await coordinator.lastFMAuthManager.handleCallback(url: url)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Set early so the iOS 26 Liquid Glass tab bar pill inherits
        // the linen background color rather than white.
        windowScene.windows.forEach { window in
            // Use a very dark olive so the Liquid Glass tab bar pill
            // reads dark content behind it and renders with a dark tint.
            window.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.15, alpha: 1.0)
        }
    }
}
