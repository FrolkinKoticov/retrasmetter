import SwiftUI

/// Simple wrapping layout (chips, words).
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - horizontalSpacing)
        }
        return CGSize(width: usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Splits the sentence into tappable segments: highlighted candidates and plain words.
struct SentenceSegment {
    let text: String
    let trailing: String
    let candidateKey: String?
}

enum SentenceSegmenter {
    static func segments(sentence: String, candidates: [VocabularyCandidate]) -> [SentenceSegment] {
        // Highlight non-overlapping spans, preferring expressions over single words.
        var chosen: [VocabularyCandidate] = []
        let byPriority = candidates.sorted { a, b in
            if a.kind != b.kind { return a.kind == .phrase }
            return sentence.distance(from: a.range.lowerBound, to: a.range.upperBound)
                 > sentence.distance(from: b.range.lowerBound, to: b.range.upperBound)
        }
        for candidate in byPriority where !chosen.contains(where: { $0.range.overlaps(candidate.range) }) {
            chosen.append(candidate)
        }
        chosen.sort { $0.range.lowerBound < $1.range.lowerBound }

        var segments: [SentenceSegment] = []
        var cursor = sentence.startIndex
        for candidate in chosen {
            guard candidate.range.lowerBound >= cursor else { continue }
            appendPlain(sentence[cursor..<candidate.range.lowerBound], to: &segments)
            var trailingEnd = candidate.range.upperBound
            while trailingEnd < sentence.endIndex, sentence[trailingEnd].isWhitespace {
                trailingEnd = sentence.index(after: trailingEnd)
            }
            segments.append(SentenceSegment(
                text: String(sentence[candidate.range]),
                trailing: String(sentence[candidate.range.upperBound..<trailingEnd]),
                candidateKey: candidate.key))
            cursor = trailingEnd
        }
        appendPlain(sentence[cursor...], to: &segments)
        return segments
    }

    /// One chunk per word, each keeping its trailing spaces.
    private static func appendPlain(_ text: Substring, to segments: inout [SentenceSegment]) {
        var current = ""
        var inSpace = false
        for character in text {
            if character.isWhitespace {
                current.append(character)
                inSpace = true
            } else {
                if inSpace, !current.isEmpty {
                    segments.append(SentenceSegment(text: current, trailing: "", candidateKey: nil))
                    current = ""
                }
                current.append(character)
                inSpace = false
            }
        }
        if !current.isEmpty { segments.append(SentenceSegment(text: current, trailing: "", candidateKey: nil)) }
    }
}

struct OverlayRootView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            switch viewModel.state {
            case .hidden:
                EmptyView()
            case .working(let message):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(message).font(.system(size: settings.overlayFontSize))
                }
            case .info(let message):
                Text(message).font(.system(size: settings.overlayFontSize, weight: .medium))
            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("Couldn’t translate"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: settings.overlayFontSize, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: settings.overlayFontSize - 2))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .result(let result):
                ResultContent(viewModel: viewModel, settings: settings, result: result)
            }
        }
        .padding(16)
        .frame(width: settings.overlayWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .onHover { viewModel.isHovering = $0 }
    }
}

private struct ResultContent: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject var settings: AppSettings
    let result: DialogueResult

    var body: some View {
        let candidates = viewModel.visibleCandidates
        let fontSize = settings.overlayFontSize

        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Text(tr("ORIGINAL"))
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(.secondary)
                if let speaker = result.speaker {
                    Text(speaker)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                Spacer()
                if let game = result.game {
                    Text(game).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            // Original sentence: the visual centre. Highlighted words are tappable.
            let segments = SentenceSegmenter.segments(sentence: result.analysis.sentence, candidates: candidates)
            FlowLayout(horizontalSpacing: 0, verticalSpacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if let key = segment.candidateKey {
                        let color: Color = viewModel.selectedKey == key ? .yellow
                            : (viewModel.vocabulary.status(forKey: key) == .learning ? .cyan : .orange)
                        (Text(segment.text).bold().foregroundColor(color).underline(true, color: color)
                         + Text(segment.trailing))
                            .onTapGesture { viewModel.select(key: key) }
                    } else {
                        Text(segment.text)
                    }
                }
            }
            .font(.system(size: fontSize + 4, weight: .semibold, design: .rounded))

            translationSection(fontSize: fontSize)

            if viewModel.showVocabulary, !candidates.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(candidates) { candidate in
                        chip(candidate)
                    }
                }
                if let selected = viewModel.selectedCandidate {
                    VocabularyPopoverView(
                        candidate: selected,
                        gloss: viewModel.glosses[selected.key],
                        currentStatus: viewModel.vocabulary.status(forKey: selected.key),
                        onMark: { viewModel.mark($0) },
                        showAnki: viewModel.settings.ankiEnabled,
                        onAnki: { viewModel.addToAnki() })
                }
            }

            if let feedback = viewModel.feedback {
                Text(feedback).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Buttons
            HStack(spacing: 8) {
                Button {
                    viewModel.showVocabulary.toggle()
                } label: {
                    Label(tr("Vocabulary") + (candidates.isEmpty ? "" : " (\(candidates.count))"), systemImage: "character.book.closed")
                }
                Button {
                    viewModel.saveSentence()
                } label: {
                    Label(viewModel.sentenceSaved ? tr("Saved") : tr("Save"), systemImage: viewModel.sentenceSaved ? "bookmark.fill" : "bookmark")
                }
                .disabled(viewModel.sentenceSaved)
                Spacer()
                Button(tr("Close")) { viewModel.close() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func translationSection(fontSize: Double) -> some View {
        if let translation = result.translation {
            if viewModel.translationRevealed {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("TRANSLATION"))
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(translation)
                        .font(.system(size: fontSize))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button(tr("Show full translation")) { viewModel.translationRevealed = true }
                    .buttonStyle(.link).controlSize(.small)
            }
        } else if let error = result.translationError {
            VStack(alignment: .leading, spacing: 4) {
                Text(error)
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Try again")) { viewModel.requestTranslation() }
                    .buttonStyle(.link).controlSize(.small)
            }
        } else if settings.mode == .immersion {
            HStack(spacing: 8) {
                Button(tr("Translate")) { viewModel.requestTranslation() }
                    .buttonStyle(.link).controlSize(.small)
                if viewModel.isTranslating { ProgressView().controlSize(.small) }
            }
        }
    }

    private func chip(_ candidate: VocabularyCandidate) -> some View {
        let status = viewModel.vocabulary.status(forKey: candidate.key)
        let selected = viewModel.selectedKey == candidate.key
        let tint: Color = status == .learning ? .cyan : .orange
        return Button {
            viewModel.select(key: candidate.key)
        } label: {
            HStack(spacing: 4) {
                if candidate.kind == .phrase { Image(systemName: "text.quote").font(.system(size: 9)) }
                Text(candidate.displayForm).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(tint.opacity(selected ? 0.38 : 0.18), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(selected ? 0.9 : 0.35)))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
