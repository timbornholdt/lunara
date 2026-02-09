import CoreGraphics
import Testing
import UIKit
@testable import Lunara

struct LinenTextureGeneratorTests {
    @Test func deterministicPixelData() {
        let size = CGSize(width: 32, height: 32)
        let base = UIColor(red: 0.96, green: 0.94, blue: 0.92, alpha: 1.0)
        let line = UIColor(red: 0.90, green: 0.88, blue: 0.85, alpha: 1.0)

        let first = LinenTextureGenerator.pixelData(
            size: size,
            base: base,
            line: line,
            seed: 42
        )
        let second = LinenTextureGenerator.pixelData(
            size: size,
            base: base,
            line: line,
            seed: 42
        )

        #expect(first == second)
        #expect(first.count == Int(size.width * size.height) * 4)
    }

    @Test func differentBaseColorsProduceDifferentOutput() {
        let size = CGSize(width: 32, height: 32)
        let lightBase = UIColor(red: 0.96, green: 0.94, blue: 0.92, alpha: 1.0)
        let darkBase = UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1.0)
        let line = UIColor(red: 0.90, green: 0.88, blue: 0.85, alpha: 1.0)

        let light = LinenTextureGenerator.pixelData(
            size: size,
            base: lightBase,
            line: line,
            seed: 42
        )
        let dark = LinenTextureGenerator.pixelData(
            size: size,
            base: darkBase,
            line: line,
            seed: 42
        )

        #expect(light != dark)
    }
}

