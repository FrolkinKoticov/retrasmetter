import Foundation
import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

/// Receives frames from the ScreenCaptureKit stream and decides *when* OCR is worth running.
///
/// Frames only live in memory: this object keeps at most two images (the newest frame and the
/// last frame that counted as "changed"). OCR is requested only after the area has been
/// visually stable for `stabilityDelay` (typewriter text), at most once per `cooldown`, and
/// never more than `maxWait` after the first change (so permanent background animation inside
/// the area cannot postpone OCR forever).
final class FrameProcessor: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Timing: Sendable {
        var stabilityDelay: TimeInterval
        var cooldown: TimeInterval
        var maxWait: TimeInterval = 2.5
    }

    /// Called off the main thread with a stable frame; the handler must call `done` when finished.
    var onStableFrame: (@Sendable (CGImage, @escaping @Sendable () -> Void) -> Void)?
    var onStop: (@Sendable (Error) -> Void)?

    private let timing: Timing
    private let detector: any FrameChangeDetector
    private let queue = DispatchQueue(label: "GameLanguageCompanion.frames", qos: .utility)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var timer: DispatchSourceTimer?

    private let lock = NSLock()
    private var latestImage: CGImage?
    private var referenceImage: CGImage?
    private var pending = false
    private var firstChange = Date.distantPast
    private var lastChange = Date.distantPast
    private var lastOCR = Date.distantPast
    private var busy = false

    init(timing: Timing, detector: any FrameChangeDetector) {
        self.timing = timing
        self.detector = detector
        super.init()
    }

    var sampleQueue: DispatchQueue { queue }

    func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stopTicking() {
        timer?.cancel()
        timer = nil
        lock.lock()
        latestImage = nil
        referenceImage = nil
        pending = false
        lock.unlock()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, isCompleteFrame(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        lock.lock()
        defer { lock.unlock() }
        latestImage = image
        if detector.hasMeaningfulChange(previous: referenceImage, current: image) {
            referenceImage = image
            let now = Date()
            if !pending { pending = true; firstChange = now }
            lastChange = now
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }

    // MARK: Scheduling

    private func tick() {
        lock.lock()
        let now = Date()
        var frame: CGImage?
        if pending, !busy, now.timeIntervalSince(lastOCR) >= timing.cooldown {
            let stable = now.timeIntervalSince(lastChange) >= timing.stabilityDelay
            let overdue = now.timeIntervalSince(firstChange) >= timing.maxWait
            if stable || overdue, let image = latestImage {
                pending = false
                busy = true
                lastOCR = now
                frame = image
            }
        }
        lock.unlock()

        guard let frame else { return }
        guard let handler = onStableFrame else { finishBusy(); return }
        handler(frame) { [weak self] in self?.finishBusy() }
    }

    private func finishBusy() {
        lock.lock()
        busy = false
        lock.unlock()
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let first = attachments.first,
              let raw = first[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
