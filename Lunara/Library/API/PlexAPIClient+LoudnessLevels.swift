import Foundation

extension PlexAPIClient {
    /// Fetches loudness level samples for a track from Plex Sonic Analysis.
    ///
    /// The Plex API exposes per-track loudness data via the full track metadata
    /// XML. When requesting with `audienceRating=1`, the response includes
    /// `<Stream>` elements with a `key` attribute pointing to the stream.
    /// Loudness levels are fetched from `/library/streams/<streamID>` with
    /// `levels=1&subSample=<N>` query params, returning comma-separated float
    /// values in the XML response body.
    ///
    /// - Parameters:
    ///   - trackID: Plex rating key for the track.
    ///   - sampleCount: Number of sub-sampled loudness bars to return. Defaults to 128.
    /// - Returns: Array of normalized [0...1] loudness levels, or nil if unavailable.
    func fetchLoudnessLevels(trackID: String, sampleCount: Int = 128) async throws -> [Float]? {
        // Step 1: Fetch full track metadata to find the audio stream ID
        let metadataEndpoint = "/library/metadata/\(trackID)"
        let metadataRequest = try await buildRequest(path: metadataEndpoint, requiresAuth: true)
        let (metadataData, _) = try await executeLoggedRequest(metadataRequest, operation: "fetchStreamID[\(trackID)]")

        // Parse the XML to find the audio stream ID
        let streamID = extractAudioStreamID(from: metadataData)
        guard let streamID else { return nil }
        let streamKey = "/library/streams/\(streamID)"

        // Step 2: Fetch loudness levels from the stream endpoint
        let levelsRequest = try await buildRequest(
            path: "\(streamKey)/levels",
            queryItems: [
                URLQueryItem(name: "subsample", value: String(sampleCount)),
            ],
            requiresAuth: true
        )
        let (levelsData, _) = try await executeLoggedRequest(levelsRequest, operation: "fetchLoudness[\(trackID)]")

        return parseLoudnessLevels(from: levelsData)
    }

    /// Extracts the audio stream ID from track metadata XML.
    private func extractAudioStreamID(from data: Data) -> String? {
        let parser = AudioStreamIDParser()
        return parser.parse(data: data)
    }

    /// Parses Level elements from the levels response XML.
    private func parseLoudnessLevels(from data: Data) -> [Float]? {
        let parser = LoudnessLevelsParser()
        guard let values = parser.parse(data: data), !values.isEmpty else { return nil }
        return normalizeToUnitRange(values)
    }

    /// Converts negative dB loudness values to a 0–1 perceptual scale.
    /// Uses dB-to-linear power conversion so differences in loudness
    /// are visually meaningful (e.g., -6 dB is twice as loud as -12 dB).
    private func normalizeToUnitRange(_ values: [Float]) -> [Float] {
        let floor: Float = -40.0
        let linear = values.map { db -> Float in
            let clamped = max(floor, min(0, db))
            // Convert dB to linear amplitude: 10^(dB/20)
            return powf(10.0, clamped / 20.0)
        }
        guard let maxVal = linear.max(), maxVal > 0 else { return linear }
        return linear.map { $0 / maxVal }
    }
}

// MARK: - XML Parsers

/// Parses track metadata XML to find the audio stream ID attribute.
private final class AudioStreamIDParser: NSObject, XMLParserDelegate {
    private var streamID: String?

    func parse(data: Data) -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return streamID
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName == "Stream",
              attributeDict["streamType"] == "2",
              let id = attributeDict["id"], !id.isEmpty else { return }
        streamID = id
        parser.abortParsing()
    }
}

/// Parses `<Level loudness="..."/>` elements from the levels response XML.
private final class LoudnessLevelsParser: NSObject, XMLParserDelegate {
    private var levels: [Float] = []

    func parse(data: Data) -> [Float]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return levels.isEmpty ? nil : levels
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName == "Level",
              let vStr = attributeDict["v"],
              let v = Float(vStr) else { return }
        levels.append(v)
    }
}
