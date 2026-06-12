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

    /// Fetches the track's loudness gain offsets from its metadata (Lunara-7g3).
    /// The gain/albumGain attrs live on the same streamType=2 Stream element as
    /// the stream ID; returns nil when the server hasn't analyzed the track.
    func fetchTrackGain(trackID: String) async throws -> TrackGain? {
        let request = try await buildRequest(path: "/library/metadata/\(trackID)", requiresAuth: true)
        let (data, _) = try await executeLoggedRequest(request, operation: "fetchTrackGain[\(trackID)]")
        let stream = AudioStreamIDParser().parseStream(data: data)
        let gain = TrackGain(gain: stream.gain, albumGain: stream.albumGain)
        return gain.isEmpty ? nil : gain
    }

    /// Extracts the audio stream ID from track metadata XML.
    private func extractAudioStreamID(from data: Data) -> String? {
        AudioStreamIDParser().parseStream(data: data).id
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

/// Parses track metadata XML for the first audio stream's ID and loudness
/// gain attrs (gain/albumGain ride the same Stream element, Lunara-7g3).
private final class AudioStreamIDParser: NSObject, XMLParserDelegate {
    struct AudioStream {
        var id: String?
        var gain: Float?
        var albumGain: Float?
    }

    private var stream = AudioStream()

    func parseStream(data: Data) -> AudioStream {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return stream
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
        stream = AudioStream(
            id: id,
            gain: attributeDict["gain"].flatMap(Float.init),
            albumGain: attributeDict["albumGain"].flatMap(Float.init)
        )
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
