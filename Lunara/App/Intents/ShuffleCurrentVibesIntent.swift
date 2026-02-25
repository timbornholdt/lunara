import AppIntents

struct ShuffleCurrentVibesIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle Current Vibes"
    static var description: IntentDescription = "Shuffles the Current Vibes collection in Lunara"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let coordinator = AppCoordinator.shared else {
            throw IntentError.coordinatorUnavailable
        }

        let collections = try await coordinator.libraryRepo.collections()
        guard let currentVibes = collections.first(where: { $0.title == "Current Vibes" }) else {
            throw IntentError.collectionNotFound
        }

        try await coordinator.shuffleCollection(currentVibes)
        return .result()
    }

    enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
        case coordinatorUnavailable
        case collectionNotFound

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .coordinatorUnavailable:
                "Lunara is not running. Please open the app first."
            case .collectionNotFound:
                "Could not find a \"Current Vibes\" collection."
            }
        }
    }
}
