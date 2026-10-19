import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplay
    case invalidRegion
    case noRegion
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return tr("Screen Recording permission is missing. Enable it in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch the app.")
        case .noDisplay:
            return tr("The display that contained the capture area is no longer available. Select the capture area again.")
        case .invalidRegion:
            return tr("The capture area is empty or outside the screen. Select it again.")
        case .noRegion:
            return tr("Select a capture area first.")
        case .failed(let message):
            return tr("Screen capture failed: %@", message)
        }
    }
}

/// One-shot screenshots of a region via ScreenCaptureKit.
/// Nothing is written to disk and nothing runs continuously.
final class ScreenCaptureManager: Sendable {
    func capture(region: CaptureRegion) async throws -> CGImage {
        guard region.width >= 4, region.height >= 4 else { throw CaptureError.invalidRegion }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // -3801: user declined / permission not granted.
            if (error as NSError).code == -3801 { throw CaptureError.permissionDenied }
            throw CaptureError.failed(error.localizedDescription)
        }

        guard let display = content.displays.first(where: { $0.displayID == region.displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Exclude our own windows so the translation overlay never ends up in the OCR input.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let displayBounds = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        let rect = region.rect.intersection(displayBounds)
        guard !rect.isNull, rect.width >= 4, rect.height >= 4 else { throw CaptureError.invalidRegion }

        let displayID = display.displayID
        let scale = await MainActor.run {
            NSScreen.screens.first(where: { $0.displayID == displayID })?.backingScaleFactor ?? 2.0
        }

        let config = SCStreamConfiguration()
        config.sourceRect = rect                                   // points, top-left origin, display-local
        config.width = max(1, Int((rect.width * scale).rounded())) // output size in pixels
        config.height = max(1, Int((rect.height * scale).rounded()))
        config.showsCursor = false

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            if (error as NSError).code == -3801 { throw CaptureError.permissionDenied }
            throw CaptureError.failed(error.localizedDescription)
        }
    }
}
