import SwiftUI

/// Lists the visible windows so the user can pick the game window.
struct WindowPickerView: View {
    @Binding var selectedID: UInt32?
    var onPick: ((GameWindowInfo) -> Void)?

    @State private var windows: [GameWindowInfo] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("Game window")).font(.headline)
                Spacer()
                Button { Task { await reload() } } label: { Label(tr("Refresh"), systemImage: "arrow.clockwise") }
                    .controlSize(.small)
            }
            if loading {
                ProgressView().controlSize(.small)
            } else if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            } else if windows.isEmpty {
                Text(tr("No windows found. Open the game and press Refresh.")).font(.caption).foregroundStyle(.secondary)
            } else {
                List(windows, selection: Binding(get: { selectedID }, set: { id in
                    selectedID = id
                    if let id, let window = windows.first(where: { $0.id == id }) { onPick?(window) }
                })) { window in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(window.appName).font(.body.weight(.medium))
                        if !window.title.isEmpty && window.title != window.appName {
                            Text(window.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(window.id)
                }
                .frame(minHeight: 140, maxHeight: 220)
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            windows = try await WindowCatalog.visibleWindows()
            errorText = nil
        } catch {
            windows = []
            errorText = error.localizedDescription
        }
    }
}
