import SwiftUI

extension StatusMonitor.Level {
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        case .unknown: return "circle.dotted"
        }
    }
    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .failure: return .red
        case .unknown: return .secondary
        }
    }
}

/// Small colored status glyph + text.
struct StatusLabel: View {
    let item: StatusMonitor.Item
    var body: some View {
        Label {
            Text(item.text)
        } icon: {
            Image(systemName: item.level.symbol).foregroundStyle(item.level.color)
        }
    }
}
