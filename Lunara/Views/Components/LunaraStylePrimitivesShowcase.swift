import SwiftUI

struct LunaraStylePrimitivesShowcase: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Style Primitives")
                .lunaraHeading(.section, weight: .semibold)

            HStack(spacing: 8) {
                ForEach(LunaraSemanticColorRole.allCases, id: \.self) { role in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.lunara(role))
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.lunara(.borderSubtle), lineWidth: 0.5)
                        )
                }
            }

            HStack(spacing: 10) {
                Button("Primary") {}
                    .buttonStyle(LunaraPillButtonStyle(role: .primary))
                Button("Secondary") {}
                    .buttonStyle(LunaraPillButtonStyle(role: .secondary))
                Button("Danger") {}
                    .buttonStyle(LunaraPillButtonStyle(role: .destructive))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.lunara(.backgroundElevated))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.lunara(.borderSubtle), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

#Preview {
    LunaraStylePrimitivesShowcase()
        .padding()
        .lunaraLinenBackground()
}
