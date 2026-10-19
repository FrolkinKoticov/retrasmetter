import CoreGraphics
import Foundation

/// Cheap "did the dialogue area change?" test that runs before OCR.
protocol FrameChangeDetector: Sendable {
    func hasMeaningfulChange(previous: CGImage?, current: CGImage) -> Bool
}

/// Compares small grayscale thumbnails cell by cell. A newly typed character changes a few
/// cells strongly, while video noise changes many cells weakly — so we count cells whose
/// brightness moved noticeably instead of averaging (an average would hide single letters).
final class LuminanceFrameChangeDetector: FrameChangeDetector, @unchecked Sendable {
    private let gridWidth = 96
    private let gridHeight = 32
    /// A cell counts as changed when its brightness moves by more than this (0…255).
    private let cellThreshold = 14
    /// Number of changed cells that makes a frame "meaningfully different".
    private let minimumChangedCells = 2

    private let lock = NSLock()
    private var cachedImage: CGImage?
    private var cachedSignature: [UInt8] = []

    func hasMeaningfulChange(previous: CGImage?, current: CGImage) -> Bool {
        guard let previous else { return true }
        guard let a = signature(of: previous), let b = signature(of: current), a.count == b.count else { return true }
        var changed = 0
        for index in 0..<a.count where abs(Int(a[index]) - Int(b[index])) > cellThreshold {
            changed += 1
            if changed >= minimumChangedCells { return true }
        }
        return false
    }

    private func signature(of image: CGImage) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedImage, cachedImage === image { return cachedSignature }

        var pixels = [UInt8](repeating: 0, count: gridWidth * gridHeight)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: gridWidth, height: gridHeight, bitsPerComponent: 8,
                bytesPerRow: gridWidth, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight))
            return true
        }
        guard drawn else { return nil }
        cachedImage = image
        cachedSignature = pixels
        return pixels
    }
}
