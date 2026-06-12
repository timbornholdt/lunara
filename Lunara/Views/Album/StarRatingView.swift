import SwiftUI

/// Five-star rating row with half-star steps (Lunara-to3).
/// Works on Plex's 0-10 integer scale: each star is worth 2, each half 1.
/// Tapping the left half of a star selects the half star, the right half the
/// full star; tapping the currently selected value clears the rating.
struct StarRatingView: View {
    /// Current rating on the Plex 0-10 scale; nil = unrated.
    let rating: Int?
    let tint: Color
    let onRate: (Int?) -> Void

    private let starSize: CGFloat = 24
    private let starSpacing: CGFloat = 6

    var body: some View {
        HStack(spacing: starSpacing) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbolName(forStar: index))
                    .font(.system(size: starSize))
                    .foregroundStyle(tint)
                    .frame(width: starSize + starSpacing, height: starSize + starSpacing)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let tappedLeftHalf = location.x < (starSize + starSpacing) / 2
                        let newRating = index * 2 + (tappedLeftHalf ? 1 : 2)
                        onRate(newRating == rating ? nil : newRating)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Album rating")
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            let current = rating ?? 0
            switch direction {
            case .increment:
                onRate(min(current + 1, 10))
            case .decrement:
                let lowered = current - 1
                onRate(lowered < 1 ? nil : lowered)
            @unknown default:
                break
            }
        }
    }

    private func symbolName(forStar index: Int) -> String {
        let value = rating ?? 0
        if value >= (index + 1) * 2 {
            return "star.fill"
        }
        if value == index * 2 + 1 {
            return "star.leadinghalf.filled"
        }
        return "star"
    }

    private var accessibilityValueText: String {
        guard let rating, rating > 0 else {
            return "Not rated"
        }
        let stars = Double(rating) / 2
        let formatted = stars.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(stars))
            : String(format: "%.1f", stars)
        return "\(formatted) of 5 stars"
    }
}

#Preview {
    VStack(spacing: 20) {
        StarRatingView(rating: nil, tint: .primary) { _ in }
        StarRatingView(rating: 7, tint: .orange) { _ in }
        StarRatingView(rating: 10, tint: .yellow) { _ in }
    }
    .padding()
}
