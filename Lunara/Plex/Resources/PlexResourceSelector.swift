import Foundation

enum PlexResourceSelector {
    static func bestServerURL(from devices: [PlexResourceDevice], preferredHost: String?) -> URL? {
        let servers = devices.filter { $0.provides.contains("server") }
        let connections = servers.flatMap { $0.connections }
        let httpsConnections = connections.filter { $0.protocolType.lowercased() == "https" }
        guard !httpsConnections.isEmpty else { return nil }

        let preferred = preferredHost?.lowercased()
        let ranked = httpsConnections.sorted { left, right in
            score(for: left, preferredHost: preferred) > score(for: right, preferredHost: preferred)
        }
        return ranked.first?.uri
    }

    private static func score(for connection: PlexResourceConnection, preferredHost: String?) -> Int {
        var score = 0
        if let preferredHost, !isIPv4Address(preferredHost) {
            if connection.address?.lowercased() == preferredHost || connection.uri.host?.lowercased() == preferredHost {
                score += 100
            }
        }
        let host = connection.uri.host?.lowercased()
        if host?.hasSuffix(".plex.direct") == true {
            score += 50
        }
        if connection.isLocal {
            score += 10
        }
        if !connection.isRelay {
            score += 5
        }
        if isPrivateHost(host) {
            score -= 100
        }
        return score
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return true
        }
    }

    private static func isPrivateHost(_ host: String?) -> Bool {
        guard let host else { return false }
        if isPrivateIPv4(host) { return true }
        if let embedded = plexDirectEmbeddedIP(host), isPrivateIPv4(embedded) { return true }
        return false
    }

    private static func plexDirectEmbeddedIP(_ host: String) -> String? {
        let parts = host.split(separator: ".")
        guard let first = parts.first else { return nil }
        let candidate = first.replacingOccurrences(of: "-", with: ".")
        return isIPv4Address(candidate) ? candidate : nil
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        guard isIPv4Address(host) else { return false }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _):
            return true
        case (192, 168):
            return true
        case (172, 16...31):
            return true
        default:
            return false
        }
    }
}
