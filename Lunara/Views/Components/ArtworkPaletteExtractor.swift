import SwiftUI
import UIKit

enum ArtworkPaletteExtractor {
    static func extract(from image: UIImage) -> ArtworkPaletteTheme {
        guard let cgImage = image.cgImage else { return .default }

        let size = 50
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        var pixelData = [UInt8](repeating: 0, count: size * size * 4)

        guard let context = CGContext(
            data: &pixelData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return .default }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var totalR: Double = 0, totalG: Double = 0, totalB: Double = 0
        var darkR: Double = 0, darkG: Double = 0, darkB: Double = 0, darkCount: Double = 0
        var vibrantR: Double = 0, vibrantG: Double = 0, vibrantB: Double = 0, maxSaturation: Double = 0

        let pixelCount = size * size
        for i in 0..<pixelCount {
            let offset = i * 4
            let r = Double(pixelData[offset]) / 255.0
            let g = Double(pixelData[offset + 1]) / 255.0
            let b = Double(pixelData[offset + 2]) / 255.0

            totalR += r; totalG += g; totalB += b

            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            if luminance < 0.4 {
                darkR += r; darkG += g; darkB += b; darkCount += 1
            }

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            if saturation > maxSaturation {
                maxSaturation = saturation
                vibrantR = r; vibrantG = g; vibrantB = b
            }
        }

        let count = Double(pixelCount)
        let avgR = totalR / count, avgG = totalG / count, avgB = totalB / count

        let bgColor: Color
        if darkCount > 0 {
            bgColor = Color(red: darkR / darkCount, green: darkG / darkCount, blue: darkB / darkCount)
        } else {
            bgColor = Color(red: avgR * 0.3, green: avgG * 0.3, blue: avgB * 0.3)
        }

        let accentColor: Color
        if maxSaturation > 0.1 {
            accentColor = Color(red: vibrantR, green: vibrantG, blue: vibrantB)
        } else {
            accentColor = Color(red: min(avgR + 0.3, 1), green: min(avgG + 0.3, 1), blue: min(avgB + 0.3, 1))
        }

        return ArtworkPaletteTheme(
            background: bgColor,
            textPrimary: .white,
            textSecondary: Color.white.opacity(0.7),
            accent: accentColor
        )
    }
}
