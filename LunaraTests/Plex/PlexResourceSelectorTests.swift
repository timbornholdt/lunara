import Foundation
import Testing
@testable import Lunara

struct PlexResourceSelectorTests {
    @Test func prefersPlexDirectOverIPWhenPreferredIsIPAddress() throws {
        let device = PlexResourceDevice(
            name: "Server",
            product: "Plex Media Server",
            provides: ["server"],
            clientIdentifier: "server-id",
            connections: [
                PlexResourceConnection(
                    uri: URL(string: "https://10.0.0.2:32400")!,
                    protocolType: "https",
                    address: "10.0.0.2",
                    isLocal: true,
                    isRelay: false
                ),
                PlexResourceConnection(
                    uri: URL(string: "https://cfc94c504ed44a5c8ec71598bd32c0a3.plex.direct:32400")!,
                    protocolType: "https",
                    address: "10.0.0.2",
                    isLocal: false,
                    isRelay: false
                )
            ]
        )

        let selected = PlexResourceSelector.bestServerURL(from: [device], preferredHost: "10.0.0.2")

        #expect(selected?.host?.hasSuffix(".plex.direct") == true)
    }

    @Test func prefersPreferredHostnameWhenNotIPAddress() throws {
        let device = PlexResourceDevice(
            name: "Server",
            product: "Plex Media Server",
            provides: ["server"],
            clientIdentifier: "server-id",
            connections: [
                PlexResourceConnection(
                    uri: URL(string: "https://example.plex.direct:32400")!,
                    protocolType: "https",
                    address: "10.0.0.2",
                    isLocal: false,
                    isRelay: false
                ),
                PlexResourceConnection(
                    uri: URL(string: "https://music.example.com:32400")!,
                    protocolType: "https",
                    address: "music.example.com",
                    isLocal: true,
                    isRelay: false
                )
            ]
        )

        let selected = PlexResourceSelector.bestServerURL(from: [device], preferredHost: "music.example.com")

        #expect(selected?.host == "music.example.com")
    }

    @Test func avoidsPrivatePlexDirectWhenRelayAvailable() throws {
        let device = PlexResourceDevice(
            name: "Server",
            product: "Plex Media Server",
            provides: ["server"],
            clientIdentifier: "server-id",
            connections: [
                PlexResourceConnection(
                    uri: URL(string: "https://192-168-1-214.cfc94c504ed44a5c8ec71598bd32c0a3.plex.direct:32400")!,
                    protocolType: "https",
                    address: "192.168.1.214",
                    isLocal: true,
                    isRelay: false
                ),
                PlexResourceConnection(
                    uri: URL(string: "https://relay.example.com:32400")!,
                    protocolType: "https",
                    address: "relay.example.com",
                    isLocal: false,
                    isRelay: true
                )
            ]
        )

        let selected = PlexResourceSelector.bestServerURL(from: [device], preferredHost: "192.168.1.214")

        #expect(selected?.host == "relay.example.com")
    }
}
