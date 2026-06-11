import SwiftUI

/// Two staggered, counter-scrolling rows of album-cover tiles — the compact
/// "hero" for collection pages (Lunara-1mu). Decorative only: it hides from
/// accessibility, freezes under Reduce Motion and while the scene is inactive
/// (no timeline runs at all in those states, so backgrounded battery cost is
/// zero), and tears down with the view when navigating away.
struct AlbumMarquee: View {
    /// Thumbnail file URLs for the collection's albums; nil entries render as
    /// muted placeholder tiles until artwork resolves.
    let thumbnailURLs: [URL?]
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let rowSpacing: CGFloat = 8
    private static let tileSpacing: CGFloat = 8
    private static let tilesPerRowMinimum = 8
    /// Slow drift, slightly different per row so the pattern never aligns.
    private static let rowSpeeds: [Double] = [14, 11]

    var body: some View {
        let tileSize = (height - Self.rowSpacing) / 2
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            row(urls: Self.paddedURLs(evenURLs, minimumCount: Self.tilesPerRowMinimum),
                tileSize: tileSize, speed: Self.rowSpeeds[0], reversed: false)
            row(urls: Self.paddedURLs(oddURLs, minimumCount: Self.tilesPerRowMinimum),
                tileSize: tileSize, speed: Self.rowSpeeds[1], reversed: true)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }

    private var evenURLs: [URL?] {
        thumbnailURLs.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
    }

    private var oddURLs: [URL?] {
        thumbnailURLs.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
    }

    private var isAnimating: Bool {
        !reduceMotion && scenePhase == .active
    }

    @ViewBuilder
    private func row(urls: [URL?], tileSize: CGFloat, speed: Double, reversed: Bool) -> some View {
        let contentWidth = CGFloat(urls.count) * (tileSize + Self.tileSpacing)
        if isAnimating {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let offset = Self.marqueeOffset(
                    elapsed: context.date.timeIntervalSinceReferenceDate,
                    speed: speed,
                    contentWidth: contentWidth
                )
                rowContent(urls: urls, tileSize: tileSize)
                    .offset(x: reversed ? -contentWidth - offset : offset)
            }
        } else {
            rowContent(urls: urls, tileSize: tileSize)
        }
    }

    /// The row's tile sequence laid out twice so the wrap never shows a gap.
    private func rowContent(urls: [URL?], tileSize: CGFloat) -> some View {
        HStack(spacing: Self.tileSpacing) {
            ForEach(Array((urls + urls).enumerated()), id: \.offset) { _, url in
                tile(url: url, size: tileSize)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tile(url: URL?, size: CGFloat) -> some View {
        Group {
            if let url {
                SquareArtworkView {
                    DownsampledThumbnail(url: url, maxPixelSize: Int(size) * 3)
                }
            } else {
                Color.lunara(.backgroundBase)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Pure helpers (unit-tested)

    /// Offset in points for a row whose content is `contentWidth` wide, sliding
    /// left at `speed` points/second and wrapping seamlessly.
    static func marqueeOffset(elapsed: TimeInterval, speed: Double, contentWidth: CGFloat) -> CGFloat {
        guard contentWidth > 0 else { return 0 }
        let distance = elapsed * speed
        return -CGFloat(distance.truncatingRemainder(dividingBy: Double(contentWidth)))
    }

    /// Repeats a short collection's covers (wrapping around the input) until the
    /// row has enough tiles to span the screen; empty input yields placeholders.
    static func paddedURLs(_ urls: [URL?], minimumCount: Int) -> [URL?] {
        guard !urls.isEmpty else {
            return Array(repeating: nil, count: minimumCount)
        }
        guard urls.count < minimumCount else { return urls }
        return (0..<minimumCount).map { urls[$0 % urls.count] }
    }
}
