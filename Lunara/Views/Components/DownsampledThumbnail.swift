import SwiftUI
import UIKit

/// Renders a LOCAL artwork file decoded at display size via DownsamplingImageLoader,
/// replacing AsyncImage in grid/list cells. AsyncImage decodes the full-resolution
/// pixel buffer (and routes even file URLs through URLSession); this decodes a
/// bounded thumbnail off the main actor instead (Lunara-gxq).
struct DownsampledThumbnail: View {
    let url: URL
    /// Largest pixel dimension of the decoded image — display points × screen scale.
    let maxPixelSize: Int

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = await Self.decode(url: url, maxPixelSize: maxPixelSize)
        }
    }

    /// Decodes off the main actor; nil when the file is missing or undecodable.
    static func decode(url: URL, maxPixelSize: Int) async -> UIImage? {
        await Task.detached {
            DownsamplingImageLoader.load(contentsOf: url, maxPixelSize: maxPixelSize)
        }.value
    }
}
