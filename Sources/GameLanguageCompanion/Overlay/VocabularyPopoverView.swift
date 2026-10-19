import SwiftUI

/// Word/expression detail card. It is drawn *inside* the overlay instead of as a SwiftUI
/// `.popover`: system popovers open their own window and tend to activate the app, which would
/// steal focus from the game.
struct VocabularyPopoverView: View {
    let candidate: VocabularyCandidate
    let gloss: WordGloss?
    let currentStatus: VocabularyStatus?
    let onMark: (VocabularyStatus) -> Void
    var showAnki: Bool = true
    let onAnki: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(candidate.displayForm).font(.system(size: 16, weight: .bold))
                if let pos = candidate.partOfSpeech {
                    Text(pos).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let currentStatus {
                    Text(currentStatus.title)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }

            if let translation = gloss?.translation ?? candidate.builtInGloss {
                Text(translation).font(.system(size: 14))
            } else if gloss == nil {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("Looking up…")).foregroundStyle(.secondary) }
                    .font(.system(size: 12))
            }

            if let definition = gloss?.definition {
                Text(definition)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                statusButton(tr("Save"), .unknown, systemImage: "bookmark")
                statusButton(tr("Learning"), .learning, systemImage: "graduationcap")
                statusButton(tr("Known"), .known, systemImage: "checkmark")
                statusButton(tr("Ignore"), .ignored, systemImage: "eye.slash")
                Spacer()
                if showAnki {
                    Button { onAnki() } label: { Label(tr("Anki"), systemImage: "rectangle.stack.badge.plus") }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusButton(_ title: String, _ status: VocabularyStatus, systemImage: String) -> some View {
        Button { onMark(status) } label: { Label(title, systemImage: systemImage) }
            .tint(currentStatus == status ? Color.accentColor : nil)
    }
}
