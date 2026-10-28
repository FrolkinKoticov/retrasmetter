import AppKit
import SwiftUI

/// Picks the dialogue box's background and text colors from the captured frame, so the translation
/// can sit in the same place without looking foreign. Works on a tiny downscaled copy; nothing is stored.
enum RegionColors {
    struct Palette {
        var background: Color
        var foreground: Color
    }

    static func sample(from image: CGImage) -> Palette? {
        let w = 48, h = max(8, min(48, 48 * image.height / max(image.width, 1)))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        // Background = most common color (quantized to 4 bits per channel).
        var counts: [Int: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let key = Int(pixels[i] >> 4) << 8 | Int(pixels[i + 1] >> 4) << 4 | Int(pixels[i + 2] >> 4)
            counts[key, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        // Average the real pixels of that bucket for an exact shade.
        var sum = (r: 0, g: 0, b: 0), n = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let key = Int(pixels[i] >> 4) << 8 | Int(pixels[i + 1] >> 4) << 4 | Int(pixels[i + 2] >> 4)
            if key == top { sum.r += Int(pixels[i]); sum.g += Int(pixels[i + 1]); sum.b += Int(pixels[i + 2]); n += 1 }
        }
        guard n > 0 else { return nil }
        let bg = (r: sum.r / n, g: sum.g / n, b: sum.b / n)

        // Text color = average of pixels far from the background.
        var fg = (r: 0, g: 0, b: 0), m = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let d = abs(Int(pixels[i]) - bg.r) + abs(Int(pixels[i + 1]) - bg.g) + abs(Int(pixels[i + 2]) - bg.b)
            if d > 200 { fg.r += Int(pixels[i]); fg.g += Int(pixels[i + 1]); fg.b += Int(pixels[i + 2]); m += 1 }
        }
        func luma(_ c: (r: Int, g: Int, b: Int)) -> Double { (0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b)) / 255 }
        var text = m >= 6 ? (r: fg.r / m, g: fg.g / m, b: fg.b / m) : (r: 255, g: 255, b: 255)
        if abs(luma(text) - luma(bg)) < 0.35 {                       // not enough contrast → fall back
            text = luma(bg) > 0.5 ? (r: 20, g: 20, b: 20) : (r: 245, g: 245, b: 245)
        }
        func color(_ c: (r: Int, g: Int, b: Int)) -> Color {
            Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
        }
        return Palette(background: color(bg), foreground: color(text))
    }
}
