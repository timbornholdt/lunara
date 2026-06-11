import SwiftUI

/// Square, clipped artwork container for grid cards. The square frame is
/// established FIRST (a flexible base color sized by aspect ratio) and the image
/// is only overlaid into it — so non-square art is center-cropped inside the
/// square instead of driving the cell's layout and bleeding into neighboring
/// cells and text (Lunara-jou). Image content should use
/// `.resizable().scaledToFill()` with NO inner flexible frame.
struct SquareArtworkView<ImageContent: View>: View {
    @ViewBuilder var imageContent: () -> ImageContent

    var body: some View {
        Color.lunara(.backgroundBase)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                imageContent()
            }
            .clipped()
    }
}
