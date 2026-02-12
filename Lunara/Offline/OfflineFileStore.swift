import CryptoKit
import Foundation

final class OfflineFileStore {
    private let baseURL: URL
    private let fileManager: FileManager

    init(baseURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseURL {
            self.baseURL = baseURL
        } else {
            self.baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Lunara", isDirectory: true)
                .appendingPathComponent("OfflineAudio", isDirectory: true)
        }
    }

    func makeTrackRelativePath(
        trackRatingKey: String,
        partKey: String?,
        fileExtension: String? = nil
    ) -> String {
        let input = "\(trackRatingKey)|\(partKey ?? "")"
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = normalizedFileExtension(fileExtension)
            ?? normalizedFileExtension(URL(string: partKey ?? "")?.pathExtension)
            ?? "mp3"
        return "tracks/\(hex).\(ext)"
    }

    func absoluteURL(forRelativePath relativePath: String) -> URL {
        baseURL.appendingPathComponent(relativePath)
    }

    func write(_ data: Data, toRelativePath relativePath: String) throws {
        let destination = absoluteURL(forRelativePath: relativePath)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    func readData(atRelativePath relativePath: String) throws -> Data? {
        let url = absoluteURL(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func removeFile(atRelativePath relativePath: String) throws {
        let url = absoluteURL(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: baseURL.path) else {
            return
        }
        try fileManager.removeItem(at: baseURL)
    }

    private func normalizedFileExtension(_ value: String?) -> String? {
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
