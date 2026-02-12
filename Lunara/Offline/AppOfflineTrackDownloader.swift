import Foundation

final class AppOfflineTrackDownloader: OfflineTrackDownloading {
    private let tokenStore: PlexAuthTokenStoring
    private let serverStore: PlexServerAddressStoring
    private let session: URLSession

    init(
        tokenStore: PlexAuthTokenStoring = PlexAuthTokenStore(keychain: KeychainStore()),
        serverStore: PlexServerAddressStoring = UserDefaultsServerAddressStore(),
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.serverStore = serverStore
        self.session = session
    }

    func downloadTrack(
        trackRatingKey: String,
        partKey: String,
        progress: @escaping @Sendable (_ bytesReceived: Int64, _ expectedBytes: Int64?) -> Void
    ) async throws -> OfflineDownloadedPayload {
        guard let serverURL = serverStore.serverURL else {
            throw OfflineRuntimeError.missingServerURL
        }
        let storedToken = try tokenStore.load()
        guard let token = storedToken else {
            throw OfflineRuntimeError.missingAuthToken
        }

        let config = PlexDefaults.configuration()
        let builder = PlexPlaybackURLBuilder(baseURL: serverURL, token: token, configuration: config)
        let url = builder.makeDirectPlayURL(partKey: partKey)

        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode) == false {
            throw OfflineRuntimeError.unexpectedHTTPStatus(httpResponse.statusCode)
        }
        let expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        progress(Int64(data.count), expected)
        return OfflineDownloadedPayload(data: data, expectedBytes: expected)
    }
}
