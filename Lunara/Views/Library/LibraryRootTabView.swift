import SwiftUI

struct LibraryRootTabView: View {
    private enum Tab: Hashable {
        case albums
        case debug
    }

    let coordinator: AppCoordinator

    @State private var selectedTab: Tab = .albums

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryGridView(
                viewModel: LibraryGridViewModel(
                    library: coordinator.libraryRepo,
                    artworkPipeline: coordinator.artworkPipeline,
                    actions: coordinator
                )
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
    }
}

#Preview {
    LibraryRootTabView(coordinator: AppCoordinator())
}
