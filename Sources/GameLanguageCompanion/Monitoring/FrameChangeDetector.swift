import CoreGraphics
import CoreVideo
import Foundation

/// A tiny grayscale fingerprint of a frame (cells of average brightness).
typealias FrameSignature = [UInt8]

/// Cheap "did the dialogue area change?" test that runs before OCR.
protocol FrameChangeDetector: Sendable {
    /// Fingerprint straight from the stream's pixel buffer — no full-size image is created.
    func signature(of pixelBuffer: CVPixelBuffer) -> FrameSignature?
    func signature(of image: CGImage) -> FrameSignature?
    func isMeaningfulChange(from previous: FrameSignature?, to current: FrameSignature) -> Bool
    /// How many grid cells changed noticeably (used to tell "text is being typed" from tiny blinking icons).
    func changedCellCount(from previous: FrameSignature?, to current: FrameSignature) -> Int
}

extension FrameChangeDetector {
    func hasMeaningfulChange(previous: CGImage?, current: CGImage) -> Bool {
        guard let current = signature(of: current) else { return true }
        return isMeaningfulChange(from: previous.flatMap { signature(of: $0) }, to: current)
    }
}

/// Compares small grayscale grids cell by cell. A newly typed character changes a few cells
/// strongly, while video noise changes many cells weakly — so we count cells whose brightness
/// moved noticeably instead of averaging (an average would hide single letters).
final class LuminanceFrameChangeDetector: FrameChangeDetector, @unchecked Sendable {
    private let gridWidth = 96
    private let gridHeight = 32
    /// A cell counts as changed when its brightness moves by more than this (0…255).
    private let cellThreshold = 14
    /// Number of changed cells that makes a frame "meaningfully different".
    private let minimumChangedCells = 2
    /// Samples per cell side when reading a pixel buffer (4×4 = 16 reads per cell).
    private let samples = 4

    func isMeaningfulChange(from previous: FrameSignature?, to current: FrameSignature) -> Bool {
        guard let previous, previous.count == current.count else { return true }
        var changed = 0
        for index in 0..<current.count where abs(Int(previous[index]) - Int(current[index])) > cellThreshold {
            changed += 1
            if changed >= minimumChangedCells { return true }
        }
        return false
    }

    func changedCellCount(from previous: FrameSignature?, to current: FrameSignature) -> Int {
        guard let previous, previous.count == current.count else { return current.count }
        var changed = 0
        for index in 0..<current.count where abs(Int(previous[index]) - Int(current[index])) > cellThreshold { changed += 1 }
        return changed
    }

    func signature(of pixelBuffer: CVPixelBuffer) -> FrameSignature? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width >= gridWidth, height >= gridHeight else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        var result = [UInt8](repeating: 0, count: gridWidth * gridHeight)
        let cellW = Double(width) / Double(gridWidth)
        let cellH = Double(height) / Double(gridHeight)
        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                var sum = 0
                for sy in 0..<samples {
                    let y = min(height - 1, Int((Double(gy) + (Double(sy) + 0.5) / Double(samples)) * cellH))
                    let row = y * stride
                    for sx in 0..<samples {
                        let x = min(width - 1, Int((Double(gx) + (Double(sx) + 0.5) / Double(samples)) * cellW))
                        let p = row + x * 4                       // B, G, R, A
                        sum += (29 * Int(bytes[p]) + 150 * Int(bytes[p + 1]) + 77 * Int(bytes[p + 2])) >> 8
                    }
                }
                result[gy * gridWidth + gx] = UInt8(sum / (samples * samples))
            }
        }
        return result
    }

    func signature(of image: CGImage) -> FrameSignature? {
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
        return drawn ? pixels : nil
    }
}
