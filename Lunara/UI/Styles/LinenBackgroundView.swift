import SwiftUI
import UIKit

struct LinenBackgroundView: View {
    let palette: LunaraTheme.PaletteColors
    let seed: UInt64
    let tileSize: CGFloat

    init(
        palette: LunaraTheme.PaletteColors,
        seed: UInt64 = 42,
        tileSize: CGFloat = 96
    ) {
        self.palette = palette
        self.seed = seed
        self.tileSize = tileSize
    }

    var body: some View {
        ZStack {
            palette.base
            if let tile = LinenTextureGenerator.tileImage(
                size: CGSize(width: tileSize, height: tileSize),
                base: palette.baseUIColor,
                line: palette.linenLineUIColor,
                seed: seed
            ) {
                Image(decorative: tile, scale: 1)
                    .resizable(resizingMode: .tile)
                    .opacity(0.06)
                    .blendMode(.multiply)
            }
        }
        .ignoresSafeArea()
    }
}

enum LinenTextureGenerator {
    struct CacheKey: Hashable {
        let width: Int
        let height: Int
        let base: UInt32
        let line: UInt32
        let seed: UInt64
    }

    private static var cache: [CacheKey: CGImage] = [:]

    static func tileImage(
        size: CGSize,
        base: UIColor,
        line: UIColor,
        seed: UInt64
    ) -> CGImage? {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        let baseRGBA = base.rgbaKey
        let lineRGBA = line.rgbaKey
        let key = CacheKey(width: width, height: height, base: baseRGBA, line: lineRGBA, seed: seed)
        if let cached = cache[key] {
            return cached
        }

        let data = pixelData(
            size: CGSize(width: width, height: height),
            base: base,
            line: line,
            seed: seed
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
        if let image {
            cache[key] = image
        }
        return image
    }

    static func pixelData(
        size: CGSize,
        base: UIColor,
        line: UIColor,
        seed: UInt64
    ) -> [UInt8] {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        let pixelCount = width * height
        var data = [UInt8](repeating: 0, count: pixelCount * 4)

        let baseComponents = base.rgbaComponents
        let lineComponents = line.rgbaComponents

        for index in 0..<pixelCount {
            let offset = index * 4
            data[offset] = baseComponents.r
            data[offset + 1] = baseComponents.g
            data[offset + 2] = baseComponents.b
            data[offset + 3] = 255
        }

        let lineAlpha: Float = 0.05
        let lineStep = 8
        for x in stride(from: 0, to: width, by: lineStep) {
            for y in 0..<height {
                blendPixel(
                    data: &data,
                    width: width,
                    x: x,
                    y: y,
                    overlay: lineComponents,
                    alpha: lineAlpha
                )
            }
        }

        for y in stride(from: 0, to: height, by: lineStep) {
            for x in 0..<width {
                blendPixel(
                    data: &data,
                    width: width,
                    x: x,
                    y: y,
                    overlay: lineComponents,
                    alpha: lineAlpha
                )
            }
        }

        var rng = SeededGenerator(seed: seed)
        for index in 0..<pixelCount {
            let offset = index * 4
            let chance = rng.nextByte()
            if chance < 14 {
                let delta: Int = rng.nextByte() < 128 ? 2 : -2
                data[offset] = clampByte(Int(data[offset]) + delta)
                data[offset + 1] = clampByte(Int(data[offset + 1]) + delta)
                data[offset + 2] = clampByte(Int(data[offset + 2]) + delta)
            }
        }

        return data
    }

    private static func blendPixel(
        data: inout [UInt8],
        width: Int,
        x: Int,
        y: Int,
        overlay: RGBAComponents,
        alpha: Float
    ) {
        let offset = (y * width + x) * 4
        data[offset] = blendChannel(base: data[offset], overlay: overlay.r, alpha: alpha)
        data[offset + 1] = blendChannel(base: data[offset + 1], overlay: overlay.g, alpha: alpha)
        data[offset + 2] = blendChannel(base: data[offset + 2], overlay: overlay.b, alpha: alpha)
    }

    private static func blendChannel(base: UInt8, overlay: UInt8, alpha: Float) -> UInt8 {
        let baseValue = Float(base)
        let overlayValue = Float(overlay)
        let blended = (baseValue * (1 - alpha)) + (overlayValue * alpha)
        return clampByte(Int(blended.rounded()))
    }

    private static func clampByte(_ value: Int) -> UInt8 {
        UInt8(max(0, min(255, value)))
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextByte() -> UInt8 {
        state = state &* 2862933555777941757 &+ 3037000493
        return UInt8(truncatingIfNeeded: state >> 24)
    }
}

private struct RGBAComponents {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

private extension UIColor {
    var rgbaComponents: RGBAComponents {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBAComponents(
            r: UInt8(red * 255),
            g: UInt8(green * 255),
            b: UInt8(blue * 255)
        )
    }

    var rgbaKey: UInt32 {
        let components = rgbaComponents
        return (UInt32(components.r) << 16) | (UInt32(components.g) << 8) | UInt32(components.b)
    }
}

