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

    @State private var isLaunching = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if coordinator.isSignedIn {
                        LibraryRootTabView(coordinator: coordinator)
                    } else {
                        SignInView(coordinator: coordinator)
                    }
                }

                if isLaunching {
                    LaunchScreenView()
                        .transition(.opacity)
                }
            }
            .id(colorSchemeManager.refreshToken)
            .environment(colorSchemeManager)
            .task {
                withAnimation(.easeOut(duration: 0.4)) {
                    isLaunching = false
                }
            }
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
            // Adapt the window background so the Liquid Glass tab bar
            // pill picks up the correct tint in both light and dark mode.
            window.backgroundColor = UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return UIColor(red: 0.0, green: 0.106, blue: 0.180, alpha: 1.0)
                } else {
                    return UIColor(red: 0.933, green: 0.953, blue: 0.976, alpha: 1.0)
                }
            }
        }
    }
}
