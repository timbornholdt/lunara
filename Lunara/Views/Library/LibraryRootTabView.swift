import SwiftUI

struct LibraryRootTabView: View {
    private enum Tab: Hashable {
        case albums
        case debug
    }

    let coordinator: AppCoordinator
    let tabBarTheme: LunaraTabBarTheme

    @State private var selectedTab: Tab = .albums

    init(coordinator: AppCoordinator, tabBarTheme: LunaraTabBarTheme = .garden) {
        self.coordinator = coordinator
        self.tabBarTheme = tabBarTheme
    }

    var body: some View {
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
        .onAppear {
            LunaraTabBarStyler.apply(theme: tabBarTheme)
        }
    }
}

#Preview {
    LibraryRootTabView(coordinator: AppCoordinator())
}
