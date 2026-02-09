import Foundation

protocol PlexHTTPClienting {
    func send<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T
    func sendData(_ request: URLRequest) async throws -> Data
}

protocol PlexAuthServicing {
    func signIn(
        login: String,
        password: String,
        verificationCode: String?,
        rememberMe: Bool
    ) async throws -> String
}

protocol PlexPinServicing {
    func createPin() async throws -> PlexPin
    func checkPin(id: Int, code: String) async throws -> PlexPinStatus
}

protocol PlexLibraryServicing {
    func fetchLibrarySections() async throws -> [PlexLibrarySection]
    func fetchAlbums(sectionId: String) async throws -> [PlexAlbum]
    func fetchTracks(albumRatingKey: String) async throws -> [PlexTrack]
}

protocol PlexResourcesServicing {
    func fetchDevices(token: String) async throws -> [PlexResourceDevice]
}

protocol PlexAuthTokenStoring {
    func save(token: String) throws
    func load() throws -> String?
    func clear() throws
}

protocol PlexServerAddressStoring {
    var serverURL: URL? { get set }
}

protocol PlexLibrarySelectionStoring {
    var selectedSectionKey: String? { get set }
}

protocol PlexTokenValidating {
    func validate(serverURL: URL, token: String) async throws
}

typealias PlexLibraryServiceFactory = (URL, String) -> PlexLibraryServicing
