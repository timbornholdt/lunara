import SwiftUI

struct ArtworkView: View {
    let request: ArtworkRequest
    let placeholder: Color
    let secondaryText: Color
    var loader: ArtworkLoader = .shared

    @State private var image: Image?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                placeholder
                if isLoading {
                    ProgressView()
                } else if didFail {
                    Text("No Art")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: request.key.cacheKeyString) {
            image = nil
            didFail = false
            await load()
        }
    }

    private func load() async {
        if image != nil || isLoading {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let uiImage = try await loader.loadImage(for: request.key, url: request.url)
            image = Image(uiImage: uiImage)
        } catch {
            didFail = true
        }
    }
}
