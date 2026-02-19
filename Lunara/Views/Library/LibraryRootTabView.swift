import SwiftUI
import UIKit

struct LibraryRootTabView: View {
    private enum Tab: Hashable {
        case albums
        case debug
    }

    let coordinator: AppCoordinator
    let tabBarTheme: LunaraTabBarTheme

    @State private var selectedTab: Tab = .albums
    private let nowPlayingBarViewModel: NowPlayingBarViewModel

    init(coordinator: AppCoordinator, tabBarTheme: LunaraTabBarTheme = .garden) {
        self.coordinator = coordinator
        self.tabBarTheme = tabBarTheme
        self.nowPlayingBarViewModel = NowPlayingBarViewModel(
            queueManager: coordinator.queueManager,
            engine: coordinator.playbackEngine,
            library: coordinator.libraryRepo,
            artworkPipeline: coordinator.artworkPipeline
        )
    }

    var body: some View {
        ZStack {
            // Covers the full screen — including the area around and below the
            // iOS 18 floating tab bar pill, which sits outside the TabView's
            // own SwiftUI layout frame and ignores .background() on the TabView.
            Color.lunara(.backgroundBase)
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
            LibraryGridView(
                viewModel: LibraryGridViewModel(
                    library: coordinator.libraryRepo,
                    artworkPipeline: coordinator.artworkPipeline,
                    actions: coordinator
                ),
                backgroundRefreshSuccessToken: coordinator.backgroundRefreshSuccessToken,
                backgroundRefreshFailureToken: coordinator.backgroundRefreshFailureToken,
                backgroundRefreshErrorMessage: coordinator.lastBackgroundRefreshErrorMessage
            )
            .tabItem {
                Label("Albums", systemImage: "square.grid.2x2")
            }
            .tag(Tab.albums)

            DebugLibraryView(coordinator: coordinator)
                .tabItem {
                    Label("Debug View", systemImage: "ladybug")
                }
                .tag(Tab.debug)
        }
            .tint(Color.lunara(tabBarTheme.selectedTintRole))
            .toolbarBackground(Color.lunara(tabBarTheme.backgroundRole), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingBar(viewModel: nowPlayingBarViewModel)
            }
            .onAppear {
                LunaraTabBarStyler.apply(theme: tabBarTheme)
                // iOS 26: the Liquid Glass tab bar is translucent and picks up
                // the UIWindow background color. Setting it here prevents the
                // default white from bleeding through the glass material and
                // into the safe area below the floating pill.
                if let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first {
                    window.backgroundColor = UIColor.lunara(.backgroundBase)
                }
            }
        }
    }
}

#Preview {
    LibraryRootTabView(coordinator: AppCoordinator())
}
