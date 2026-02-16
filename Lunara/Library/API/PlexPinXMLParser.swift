import Foundation

// MARK: - Plex Pin XML Parser

/// Simple XML parser for Plex OAuth pin responses
/// Plex returns XML like: <pin id="123" code="ABCD" authToken="xyz" />
final class PlexPinXMLParser: NSObject, XMLParserDelegate {

    private var pinAttributes: [String: String] = [:]

    func parse(data: Data) -> [String: String]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        pinAttributes.removeAll()

        guard parser.parse() else {
            return nil
        }

        return pinAttributes.isEmpty ? nil : pinAttributes
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "pin" {
            pinAttributes = attributeDict
        }
    }
}
