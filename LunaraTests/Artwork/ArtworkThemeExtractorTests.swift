import Foundation
import Testing
import UIKit
@testable import Lunara

@MainActor
struct ArtworkThemeExtractorTests {
    @Test func dominantColorMatchesMajorityPixels() {
        let image = TestImageFactory.imageWithSplitColors(
            size: CGSize(width: 20, height: 20),
            primary: UIColor.red,
            secondary: UIColor.blue,
            primaryRatio: 0.75
        )

        let theme = ArtworkThemeExtractor.extractTheme(from: image)

        let dominant = theme?.dominantColor
        let secondary = theme?.secondaryColor

        #expect(dominant != nil)
        #expect(secondary != nil)
        #expect(ColorDistance.isClose(dominant, to: UIColor.red, tolerance: 0.15))
    }

    @Test func textContrastMeetsMinimum() {
        let image = TestImageFactory.imageWithSolidColor(
            size: CGSize(width: 10, height: 10),
            color: UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        )

        let theme = ArtworkThemeExtractor.extractTheme(from: image)
        let background = theme?.backgroundTop
        let text = theme?.textPrimary

        #expect(background != nil)
        #expect(text != nil)
        #expect(ContrastCalculator.contrastRatio(
            foreground: text ?? .white,
            background: background ?? .black
        ) >= 4.5)
    }
}

private enum TestImageFactory {
    static func imageWithSolidColor(size: CGSize, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func imageWithSplitColors(
        size: CGSize,
        primary: UIColor,
        secondary: UIColor,
        primaryRatio: CGFloat
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let primaryWidth = size.width * primaryRatio
            primary.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: primaryWidth, height: size.height))
            secondary.setFill()
            ctx.fill(CGRect(x: primaryWidth, y: 0, width: size.width - primaryWidth, height: size.height))
        }
    }
}

private enum ColorDistance {
    static func isClose(_ color: UIColor?, to target: UIColor, tolerance: CGFloat) -> Bool {
        guard let color else { return false }
        let c1 = color.rgbaComponents
        let c2 = target.rgbaComponents
        let dr = CGFloat(c1.r) - CGFloat(c2.r)
        let dg = CGFloat(c1.g) - CGFloat(c2.g)
        let db = CGFloat(c1.b) - CGFloat(c2.b)
        let distance = sqrt(dr * dr + dg * dg + db * db) / 255.0
        return distance <= tolerance
    }
}

private extension UIColor {
    var rgbaComponents: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (
            r: UInt8(red * 255),
            g: UInt8(green * 255),
            b: UInt8(blue * 255),
            a: UInt8(alpha * 255)
        )
    }
}
