import Foundation
import Testing
@testable import Lunara

struct PlexResourcesParserTests {
    @Test func parsesDevicesAndConnections() throws {
        let xml = """
        <MediaContainer size=\"2\">
          <Device name=\"Server\" product=\"Plex Media Server\" provides=\"server\" clientIdentifier=\"server-id\">
            <Connection protocol=\"https\" address=\"10.0.0.2\" port=\"32400\" uri=\"https://cfc94c504ed44a5c8ec71598bd32c0a3.plex.direct:32400\" local=\"1\" relay=\"0\"/>
          </Device>
          <Device name=\"Player\" product=\"Plexamp\" provides=\"player\" clientIdentifier=\"player-id\">
            <Connection protocol=\"https\" address=\"10.0.0.3\" port=\"32400\" uri=\"https://10.0.0.3:32400\" local=\"1\" relay=\"0\"/>
          </Device>
        </MediaContainer>
        """
        let parser = PlexResourcesXMLParser()
        let devices = try parser.parse(data: Data(xml.utf8))

        #expect(devices.count == 2)
        #expect(devices[0].provides == ["server"])
        #expect(devices[0].connections.count == 1)
        #expect(devices[0].connections[0].uri.host == "cfc94c504ed44a5c8ec71598bd32c0a3.plex.direct")
        #expect(devices[1].product == "Plexamp")
    }
}
