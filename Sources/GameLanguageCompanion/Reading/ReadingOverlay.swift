import AppKit
import SwiftUI

/// Panel that can be clicked without activating the app, so the game keeps keyboard focus.
final class ReadingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// State of the transparent word layer.
@MainActor
final class ReadingModel: ObservableObject {
    @Published var dialogue: CurrentDialogue?
    @Published var hoveredIndex: Int?
    @Published var selection: ClosedRange<Int>?
    /// Frame of the panel in global AppKit coordinates (needed to convert word boxes).
    var panelFrame: CGRect = .zero

    /// Word box in the panel's SwiftUI coordinates (top-left origin).
    func localRect(_ word: RecognizedWord) -> CGRect {
        CGRect(x: word.boundingBox.minX - panelFrame.minX,
               y: panelFrame.maxY - word.boundingBox.maxY,
               width: word.boundingBox.width, height: word.boundingBox.height)
    }

    /// Index of the word under `point` (panel coordinates). With `nearest`, the closest word
    /// within a generous distance is returned — used while dragging across gaps.
    func wordIndex(at point: CGPoint, nearest: Bool) -> Int? {
        guard let words = dialogue?.words else { return nil }
        var best: (index: Int, distance: CGFloat)?
        for (index, word) in words.enumerated() {
            let rect = localRect(word)
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            let distance = (dx * dx + dy * dy).squareRoot()
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        guard let best else { return nil }
        return best.distance <= (nearest ? 40 : 4) ? best.index : nil
    }
}

/// Almost invisible layer over the dialogue: words get a subtle highlight on hover/selection.
/// A tap selects one word, a drag selects a run of words.
struct ReadingOverlayView: View {
    @ObservedObject var model: ReadingModel
    let onSelect: (ClosedRange<Int>) -> Void

    @State private var anchor: Int?
    @State private var anchorResolved = false
    @State private var moved = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Nearly transparent, but not click-through: the layer must catch the mouse.
            Color.black.opacity(0.001)

            if let dialogue = model.dialogue {
                ForEach(Array(dialogue.words.enumerated()), id: \.element.id) { index, word in
                    let rect = model.localRect(word)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fill(for: index))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1)
                        }
                        .frame(width: rect.width + 4, height: rect.height + 2)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !anchorResolved {
                        anchor = model.wordIndex(at: value.startLocation, nearest: false)
                        anchorResolved = true
                        moved = false
                    }
                    guard let anchor else { return }
                    let distance = hypot(value.translation.width, value.translation.height)
                    if distance > 4 { moved = true }
                    let current = model.wordIndex(at: value.location, nearest: true) ?? anchor
                    model.selection = min(anchor, current)...max(anchor, current)
                }
                .onEnded { _ in
                    defer { anchor = nil; anchorResolved = false; moved = false }
                    guard anchor != nil, let selection = model.selection else { return }
                    onSelect(selection)
                }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): model.hoveredIndex = model.wordIndex(at: point, nearest: false)
            case .ended: model.hoveredIndex = nil
            }
        }
    }

    private func fill(for index: Int) -> Color {
        if let selection = model.selection, selection.contains(index) { return Color.accentColor.opacity(0.38) }
        if model.hoveredIndex == index { return Color.white.opacity(0.22) }
        return Color.white.opacity(0.05)
    }
}
