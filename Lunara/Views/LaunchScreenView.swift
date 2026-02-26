import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        VStack {
            Spacer()

            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lunaraLinenBackground()
    }
}
