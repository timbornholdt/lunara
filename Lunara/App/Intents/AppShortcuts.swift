import AppIntents

struct LunaraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShuffleCurrentVibesIntent(),
            phrases: [
                "Shuffle Current Vibes in \(.applicationName)",
                "Play Current Vibes in \(.applicationName)"
            ],
            shortTitle: "Shuffle Current Vibes",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: ShuffleAllAlbumsIntent(),
            phrases: [
                "Shuffle all albums in \(.applicationName)",
                "Play all albums in \(.applicationName)"
            ],
            shortTitle: "Shuffle All Albums",
            systemImageName: "shuffle"
        )
    }
}
