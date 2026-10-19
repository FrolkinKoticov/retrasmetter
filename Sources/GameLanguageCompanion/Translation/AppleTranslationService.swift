import Foundation
import AppKit
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Apple's on-device Translation framework (macOS 15+). Free, offline, private.
///
/// `TranslationSession` can only be obtained through SwiftUI's `.translationTask` modifier
/// on macOS 15, so a tiny invisible host window carries that modifier and
/// `AppleTranslationBridge` turns it into a plain async call.
struct AppleTranslationService: TranslationService {
    let name = "Apple Translation"

    func translate(_ text: String, from sourceLanguage: Language, to targetLanguage: Language) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            let translated = try await AppleTranslationBridge.shared.translate(trimmed, from: sourceLanguage, to: targetLanguage)
            return TranslationResult(sourceText: trimmed, translatedText: translated,
                                     sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, provider: name)
        }
        #endif
        throw TranslationError.unavailable(tr("Apple Translation requires macOS 15 or newer."))
    }
}

#if canImport(Translation)

@available(macOS 15.0, *)
@MainActor
final class AppleTranslationBridge: ObservableObject {
    static let shared = AppleTranslationBridge()

    @Published var configuration: TranslationSession.Configuration?

    private struct Pending {
        let id: UUID
        let text: String
        let continuation: CheckedContinuation<String, Error>
    }

    private var pending: Pending?
    private var hostWindow: NSWindow?

    // Simple async mutex: only one translation uses the shared session at a time.
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates the invisible window that hosts `.translationTask`. Call once at launch.
    func installHostIfNeeded() {
        guard hostWindow == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1, height: 1),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: TranslationHostView(bridge: self))
        window.orderBack(nil)
        hostWindow = window
    }

    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let availability = LanguageAvailability()
        let status = await availability.status(from: source.localeLanguage, to: target.localeLanguage)
        if status == .unsupported {
            throw TranslationError.unavailable(tr("Apple Translation does not support %@ → %@.", source.displayName, target.displayName))
        }
        if status == .supported {
            // Supported but not installed: the hidden host window cannot show the download sheet.
            throw TranslationError.unavailable(
                tr("The %@ → %@ language pack is not downloaded yet. Open System Settings → General → Language & Region → Translation Languages and download both languages (or use this app’s Settings → Translation → Download / Check…).", source.displayName, target.displayName))
        }
        installHostIfNeeded()

        await acquire()
        defer { release() }

        return try await withCheckedThrowingContinuation { continuation in
            let request = Pending(id: UUID(), text: text, continuation: continuation)
            pending = request

            let wanted = TranslationSession.Configuration(source: source.localeLanguage, target: target.localeLanguage)
            if configuration == wanted {
                configuration?.invalidate()      // same languages: re-run the translation task
            } else {
                configuration = wanted
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                self?.finish(id: request.id, result: .failure(TranslationError.timedOut))
            }
        }
    }

    /// Called from the SwiftUI `.translationTask` action.
    func handle(_ session: TranslationSession) async {
        guard let request = pending else { return }
        do {
            let response = try await session.translate(request.text)
            finish(id: request.id, result: .success(response.targetText))
        } catch {
            finish(id: request.id, result: .failure(TranslationError.providerFailed(error.localizedDescription)))
        }
    }

    private func finish(id: UUID, result: Result<String, Error>) {
        guard let request = pending, request.id == id else { return }
        pending = nil
        request.continuation.resume(with: result)
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

@available(macOS 15.0, *)
private struct TranslationHostView: View {
    @ObservedObject var bridge: AppleTranslationBridge
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.configuration) { session in
                await bridge.handle(session)
            }
    }
}

/// Settings UI: shows whether the language pack is installed and lets the user download it
/// (the system download sheet needs a visible window, which the hidden host cannot provide).
@available(macOS 15.0, *)
struct AppleTranslationSetupSection: View {
    @ObservedObject var settings: AppSettings
    @State private var statusText = tr("Checking…")
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        HStack {
            Text(tr("Language pack: %@", statusText))
            Spacer()
            Button(tr("Download / Check…")) {
                configuration = .init(source: settings.sourceLanguage.localeLanguage,
                                      target: settings.targetLanguage.localeLanguage)
            }
        }
        .task(id: "\(settings.sourceLanguage.code)-\(settings.targetLanguage.code)") { await refresh() }
        .translationTask(configuration) { session in
            do { try await session.prepareTranslation() } catch { /* user cancelled */ }
            await refresh()
        }
    }

    private func refresh() async {
        let status = await LanguageAvailability().status(
            from: settings.sourceLanguage.localeLanguage, to: settings.targetLanguage.localeLanguage)
        switch status {
        case .installed: statusText = tr("installed")
        case .supported: statusText = tr("not downloaded yet")
        case .unsupported: statusText = tr("pair not supported")
        @unknown default: statusText = tr("unknown")
        }
    }
}

#endif
