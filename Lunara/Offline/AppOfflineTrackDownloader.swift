import Foundation
import UniformTypeIdentifiers

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
        let suggestedExtension = resolveFileExtension(
            response: response,
            requestedURL: url,
            partKey: partKey
        )
        progress(Int64(data.count), expected)
        return OfflineDownloadedPayload(
            data: data,
            expectedBytes: expected,
            suggestedFileExtension: suggestedExtension
        )
    }

    private func resolveFileExtension(
        response: URLResponse,
        requestedURL: URL,
        partKey: String
    ) -> String? {
        let mimeExtension = response.mimeType
            .flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
            .flatMap(normalizeFileExtension)

        let responseExtension = normalizeFileExtension(response.url?.pathExtension)
        let requestedExtension = normalizeFileExtension(requestedURL.pathExtension)
        let partExtension = normalizeFileExtension(URL(string: partKey)?.pathExtension)

        return mimeExtension ?? responseExtension ?? requestedExtension ?? partExtension
    }

    private func normalizeFileExtension(_ value: String?) -> String? {
        guard var ext = value?.trimmingCharacters(in: .whitespacesAndNewlines), ext.isEmpty == false else {
            return nil
        }
        if ext.hasPrefix(".") {
            ext.removeFirst()
        }
        ext = ext.lowercased()
        let allowed = CharacterSet.alphanumerics
        let filteredScalars = ext.unicodeScalars.filter { allowed.contains($0) }
        let filtered = String(String.UnicodeScalarView(filteredScalars))
        guard filtered.isEmpty == false else { return nil }
        return filtered
    }
}
