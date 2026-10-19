import AppKit

/// A user-selected capture rectangle.
///
/// Coordinates are **display-local points with a top-left origin** — exactly what
/// `SCStreamConfiguration.sourceRect` expects. That makes the region independent of
/// Retina scale (pixels are derived at capture time) and of where the display sits in
/// the global desktop arrangement.
struct CaptureRegion: Codable, Equatable, Sendable {
    var displayID: UInt32
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(displayID: UInt32, rect: CGRect) {
        self.displayID = displayID
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// The region in global AppKit screen coordinates (bottom-left origin).
    var screenFrame: CGRect? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) ?? NSScreen.main else { return nil }
        return CGRect(x: screen.frame.minX + x, y: screen.frame.maxY - (y + height), width: width, height: height)
    }

    var summary: String { tr("%d × %d pt at (%d, %d)", Int(width), Int(height), Int(x), Int(y)) }
}

extension NSScreen {
    /// The CoreGraphics display ID (matches `SCDisplay.displayID`).
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
