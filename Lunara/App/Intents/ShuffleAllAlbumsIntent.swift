import AppIntents

struct ShuffleAllAlbumsIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle All Albums"
    static var description: IntentDescription = "Shuffles all albums in your Lunara library"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let coordinator = AppCoordinator.shared else {
            throw IntentError.coordinatorUnavailable
        }

        try await coordinator.shuffleAllAlbums()
        return .result()
    }

    enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
        case coordinatorUnavailable

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .coordinatorUnavailable:
                "Lunara is not running. Please open the app first."
            }
        }
    }
}
