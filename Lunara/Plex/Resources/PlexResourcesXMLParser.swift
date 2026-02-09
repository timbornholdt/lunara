import Foundation

struct PlexResourcesXMLParser {
    func parse(data: Data) throws -> [PlexResourceDevice] {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        if parser.parse() {
            return delegate.devices
        }
        if let error = parser.parserError {
            throw error
        }
        throw PlexResourcesParseError.invalidXML
    }
}

enum PlexResourcesParseError: Error {
    case invalidXML
}

private final class Delegate: NSObject, XMLParserDelegate {
    fileprivate var devices: [PlexResourceDevice] = []
    private var currentDevice: PlexResourceDeviceBuilder?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "Device":
            currentDevice = PlexResourceDeviceBuilder(
                name: attributeDict["name"] ?? "",
                product: attributeDict["product"] ?? "",
                provides: attributeDict["provides"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [],
                clientIdentifier: attributeDict["clientIdentifier"] ?? "",
                connections: []
            )
        case "Connection":
            guard var currentDevice else { return }
            guard let uriString = attributeDict["uri"], let uri = URL(string: uriString) else { return }
            let connection = PlexResourceConnection(
                uri: uri,
                protocolType: attributeDict["protocol"] ?? "",
                address: attributeDict["address"],
                isLocal: attributeDict["local"] == "1",
                isRelay: attributeDict["relay"] == "1"
            )
            currentDevice.connections.append(connection)
            self.currentDevice = currentDevice
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "Device", let currentDevice else { return }
        devices.append(currentDevice.build())
        self.currentDevice = nil
    }
}

private struct PlexResourceDeviceBuilder {
    let name: String
    let product: String
    let provides: [String]
    let clientIdentifier: String
    var connections: [PlexResourceConnection]

    func build() -> PlexResourceDevice {
        PlexResourceDevice(
            name: name,
            product: product,
            provides: provides,
            clientIdentifier: clientIdentifier,
            connections: connections
        )
    }
}
