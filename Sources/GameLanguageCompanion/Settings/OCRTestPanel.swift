import SwiftUI

/// "Test OCR": captures the saved area, runs Apple Vision and shows what was read.
/// Used in Settings and in the onboarding wizard to diagnose setup problems.
struct OCRTestPanel: View {
    let appState: AppState
    @ObservedObject var settings: AppSettings

    @State private var running = false
    @State private var output: String?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(tr("Test OCR")) { Task { await run() } }
                    .disabled(running || settings.captureRegion == nil)
                if running { ProgressView().controlSize(.small) }
            }
            if let errorText {
                Label(errorText, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let output {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Recognized text:")).font(.caption).foregroundStyle(.secondary)
                    Text(output.isEmpty ? tr("No text was recognized in the capture area. Re-select the area so it tightly covers the subtitle text.") : output)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func run() async {
        running = true
        errorText = nil
        output = nil
        do {
            output = try await appState.coordinator.recognizeCurrentRegion()
        } catch {
            errorText = error.localizedDescription
        }
        running = false
    }
}
