import Foundation

struct PlexTokenValidator: PlexTokenValidating {
    let libraryServiceFactory: PlexLibraryServiceFactory

    func validate(serverURL: URL, token: String) async throws {
        _ = try await libraryServiceFactory(serverURL, token).fetchLibrarySections()
    }
}
