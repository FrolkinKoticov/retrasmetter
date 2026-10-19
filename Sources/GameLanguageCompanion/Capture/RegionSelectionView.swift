import SwiftUI

/// Full-screen dimmed canvas where the user drags a rectangle.
/// The view fills one screen, so SwiftUI's top-left local coordinates are already the
/// display-local, top-left-origin points that `CaptureRegion` stores.
struct RegionSelectionView: View {
    var onSelect: (CGRect) -> Void
    var onCancel: () -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Canvas { context, size in
                var dim = Path(CGRect(origin: .zero, size: size))
                if let rect = selection { dim.addRect(rect) }
                // Even-odd fill leaves the selected rectangle un-dimmed.
                context.fill(dim, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                if let rect = selection {
                    context.stroke(Path(rect), with: .color(.white), lineWidth: 2)
                    context.stroke(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(.accentColor),
                                   style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                }
            }

            VStack(spacing: 6) {
                Text(selection == nil
                     ? tr("Drag over the area where the game shows its dialogue")
                     : "\(Int(selection!.width)) × \(Int(selection!.height))")
                    .font(.system(size: 15, weight: .semibold))
                Text(tr("Esc to cancel"))
                    .font(.system(size: 12))
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 60)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if start == nil { start = value.startLocation }
                    current = value.location
                }
                .onEnded { value in
                    current = value.location
                    let rect = selection
                    start = nil
                    current = nil
                    if let rect, rect.width >= 20, rect.height >= 12 {
                        onSelect(rect)
                    }
                }
        )
        .onContinuousHover { _ in NSCursor.crosshair.set() }
        .ignoresSafeArea()
    }
}
