import Foundation

struct PlexResourceDevice: Equatable, Sendable {
    let name: String
    let product: String
    let provides: [String]
    let clientIdentifier: String
    let connections: [PlexResourceConnection]
}

struct PlexResourceConnection: Equatable, Sendable {
    let uri: URL
    let protocolType: String
    let address: String?
    let isLocal: Bool
    let isRelay: Bool
}
