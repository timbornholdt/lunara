import Foundation
import UIKit

struct ArtworkTheme {
    let dominantColor: UIColor
    let secondaryColor: UIColor
    let backgroundTop: UIColor
    let backgroundBottom: UIColor
    let textPrimary: UIColor
    let textSecondary: UIColor
    let accentPrimary: UIColor
    let accentSecondary: UIColor
    let raised: UIColor
    let borderSubtle: UIColor
    let linenLine: UIColor
}

enum ArtworkThemeExtractor {
    static func extractTheme(from image: UIImage) -> ArtworkTheme? {
        guard let pixels = PixelSampler.samplePixels(from: image, maxDimension: 64),
              !pixels.isEmpty else { return nil }
        let clusters = KMeans.cluster(pixels: pixels, k: 3, iterations: 6)
        guard let dominant = clusters.first?.color else { return nil }
        let secondary = clusters.dropFirst().first?.color ?? dominant

        let backgroundTop = dominant
        let backgroundBottom = ColorAdjuster.blend(dominant, secondary, ratio: 0.45)
        let accentPrimary = ColorAdjuster.adjustSaturation(dominant, factor: 1.15)
        let accentSecondary = ColorAdjuster.adjustSaturation(secondary, factor: 1.1)

        let textPrimary = ContrastCalculator.bestTextColor(
            for: backgroundTop,
            minimumRatio: 4.5
        )
        let textSecondary = ContrastCalculator.bestTextColor(
            for: backgroundBottom,
            minimumRatio: 4.5
        )

        let raised = ColorAdjuster.adjustBrightness(backgroundTop, factor: 1.08)
        let borderSubtle = ColorAdjuster.adjustBrightness(backgroundTop, factor: 0.9)
        let linenLine = ColorAdjuster.adjustBrightness(backgroundTop, factor: 0.85)

        return ArtworkTheme(
            dominantColor: dominant,
            secondaryColor: secondary,
            backgroundTop: backgroundTop,
            backgroundBottom: backgroundBottom,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accentPrimary: accentPrimary,
            accentSecondary: accentSecondary,
            raised: raised,
            borderSubtle: borderSubtle,
            linenLine: linenLine
        )
    }
}

enum ContrastCalculator {
    static func contrastRatio(foreground: UIColor, background: UIColor) -> CGFloat {
        let l1 = relativeLuminance(foreground)
        let l2 = relativeLuminance(background)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func bestTextColor(for background: UIColor, minimumRatio: CGFloat) -> UIColor {
        let white = UIColor.white
        let black = UIColor.black
        let whiteRatio = contrastRatio(foreground: white, background: background)
        let blackRatio = contrastRatio(foreground: black, background: background)
        if whiteRatio >= minimumRatio || whiteRatio >= blackRatio {
            return white
        }
        return black
    }

    private static func relativeLuminance(_ color: UIColor) -> CGFloat {
        let components = color.rgbaComponents
        let r = linearize(CGFloat(components.r) / 255.0)
        let g = linearize(CGFloat(components.g) / 255.0)
        let b = linearize(CGFloat(components.b) / 255.0)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func linearize(_ value: CGFloat) -> CGFloat {
        if value <= 0.03928 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
}

private enum PixelSampler {
    static func samplePixels(from image: UIImage, maxDimension: Int) -> [RGBPixel]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = min(cgImage.width, maxDimension)
        let height = min(cgImage.height, maxDimension)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var pixels: [RGBPixel] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = buffer[offset]
                let g = buffer[offset + 1]
                let b = buffer[offset + 2]
                let a = buffer[offset + 3]
                guard a > 24 else { continue }
                pixels.append(RGBPixel(r: Double(r), g: Double(g), b: Double(b)))
            }
        }
        return pixels
    }
}

private struct RGBPixel {
    let r: Double
    let g: Double
    let b: Double

    func distance(to other: RGBPixel) -> Double {
        let dr = r - other.r
        let dg = g - other.g
        let db = b - other.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    func toUIColor() -> UIColor {
        UIColor(
            red: CGFloat(r / 255.0),
            green: CGFloat(g / 255.0),
            blue: CGFloat(b / 255.0),
            alpha: 1.0
        )
    }
}

private struct KMeansCluster {
    var color: UIColor
    var centroid: RGBPixel
    var count: Int
}

private enum KMeans {
    static func cluster(pixels: [RGBPixel], k: Int, iterations: Int) -> [KMeansCluster] {
        guard !pixels.isEmpty else { return [] }
        let centroids = initialCentroids(from: pixels, k: k)
        var clusters = centroids.map { KMeansCluster(color: $0.toUIColor(), centroid: $0, count: 0) }

        for _ in 0..<iterations {
            var sums = Array(repeating: RGBPixel(r: 0, g: 0, b: 0), count: clusters.count)
            var counts = Array(repeating: 0, count: clusters.count)

            for pixel in pixels {
                let index = nearestClusterIndex(for: pixel, clusters: clusters)
                let current = sums[index]
                sums[index] = RGBPixel(
                    r: current.r + pixel.r,
                    g: current.g + pixel.g,
                    b: current.b + pixel.b
                )
                counts[index] += 1
            }

            for index in clusters.indices {
                guard counts[index] > 0 else { continue }
                let sum = sums[index]
                let centroid = RGBPixel(
                    r: sum.r / Double(counts[index]),
                    g: sum.g / Double(counts[index]),
                    b: sum.b / Double(counts[index])
                )
                clusters[index].centroid = centroid
                clusters[index].color = centroid.toUIColor()
                clusters[index].count = counts[index]
            }
        }

        return clusters.sorted { $0.count > $1.count }
    }

    private static func initialCentroids(from pixels: [RGBPixel], k: Int) -> [RGBPixel] {
        guard k > 0 else { return [] }
        var centroids: [RGBPixel] = []
        let stride = max(pixels.count / k, 1)
        var index = 0
        while centroids.count < k && index < pixels.count {
            centroids.append(pixels[index])
            index += stride
        }
        if centroids.isEmpty, let first = pixels.first {
            centroids = [first]
        }
        return centroids
    }

    private static func nearestClusterIndex(for pixel: RGBPixel, clusters: [KMeansCluster]) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, cluster) in clusters.enumerated() {
            let distance = pixel.distance(to: cluster.centroid)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}

private enum ColorAdjuster {
    static func blend(_ first: UIColor, _ second: UIColor, ratio: CGFloat) -> UIColor {
        let c1 = first.rgbaComponents
        let c2 = second.rgbaComponents
        let r = CGFloat(c1.r) * (1 - ratio) + CGFloat(c2.r) * ratio
        let g = CGFloat(c1.g) * (1 - ratio) + CGFloat(c2.g) * ratio
        let b = CGFloat(c1.b) * (1 - ratio) + CGFloat(c2.b) * ratio
        return UIColor(
            red: r / 255.0,
            green: g / 255.0,
            blue: b / 255.0,
            alpha: 1.0
        )
    }

    static func adjustBrightness(_ color: UIColor, factor: CGFloat) -> UIColor {
        let components = color.rgbaComponents
        let r = min(max(CGFloat(components.r) * factor, 0), 255)
        let g = min(max(CGFloat(components.g) * factor, 0), 255)
        let b = min(max(CGFloat(components.b) * factor, 0), 255)
        return UIColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1.0)
    }

    static func adjustSaturation(_ color: UIColor, factor: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }
        return UIColor(
            hue: hue,
            saturation: min(saturation * factor, 1.0),
            brightness: brightness,
            alpha: alpha
        )
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
