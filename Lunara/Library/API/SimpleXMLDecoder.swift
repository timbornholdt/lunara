import Foundation

// MARK: - SimpleXMLDecoder

/// Basic XML decoder for Plex API responses
/// Handles Plex's simple XML structure with MediaContainer and Metadata elements
final class SimpleXMLDecoder: NSObject, XMLParserDelegate {

    enum XMLDecodingError: Error {
        case invalidXML
        case parsingFailed(String)
    }

    private var currentElement = ""
    private var currentAttributes: [String: String] = [:]
    private var metadataItems: [[String: String]] = []
    private var isParsingMetadata = false

    func decode(_ data: Data) throws -> PlexMediaContainer {
        let parser = XMLParser(data: data)
        parser.delegate = self
        metadataItems.removeAll()

        guard parser.parse() else {
            throw XMLDecodingError.invalidXML
        }

        // Convert parsed attributes to PlexMetadata objects
        let metadata = metadataItems.map { attrs -> PlexMetadata in
            let ratingKey = attrs["ratingKey"] ?? ""
            let title = attrs["title"] ?? ""
            let type = attrs["type"] ?? ""
            let index = attrs["index"].flatMap { Int($0) }
            let year = attrs["year"].flatMap { Int($0) }
            let duration = attrs["duration"].flatMap { Int($0) }
            let rating = attrs["rating"].flatMap { Double($0) }
            let addedAt = attrs["addedAt"].flatMap { Int($0) }
            let trackCount = attrs["leafCount"].flatMap { Int($0) }
            let albumCount = attrs["childCount"].flatMap { Int($0) }

            return PlexMetadata(
                ratingKey: ratingKey,
                title: title,
                parentRatingKey: attrs["parentRatingKey"],
                grandparentRatingKey: attrs["grandparentRatingKey"],
                type: type,
                index: index,
                parentTitle: attrs["parentTitle"],
                grandparentTitle: attrs["grandparentTitle"],
                year: year,
                thumb: attrs["thumb"],
                duration: duration,
                genre: attrs["genre"],
                rating: rating,
                addedAt: addedAt,
                trackCount: trackCount,
                albumCount: albumCount,
                summary: attrs["summary"],
                titleSort: attrs["titleSort"],
                key: attrs["key"]
            )
        }

        return PlexMediaContainer(metadata: metadata.isEmpty ? nil : metadata)
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        if elementName == "Metadata" {
            // Store all attributes for this Metadata element
            metadataItems.append(attributeDict)
            isParsingMetadata = true
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "Metadata" {
            isParsingMetadata = false
        }
    }
}

// MARK: - XMLDecoder Replacement

/// Type alias for clarity - we're using SimpleXMLDecoder
typealias XMLDecoder = SimpleXMLDecoder

extension XMLDecoder {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // Only supports PlexMediaContainer decoding
        if type == PlexMediaContainer.self {
            return try decode(data) as! T
        }
        throw SimpleXMLDecoder.XMLDecodingError.parsingFailed("Unsupported type")
    }
}
