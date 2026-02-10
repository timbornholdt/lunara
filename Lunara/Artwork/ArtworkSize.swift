import Foundation

enum ArtworkSize: Int, Codable, Sendable {
    case grid = 1024
    case detail = 2048

    var maxPixelSize: Int { rawValue }
}
