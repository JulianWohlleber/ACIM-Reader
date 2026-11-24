import SwiftUI
import UIKit

extension NSAttributedString.Key {
    /// Carries the global sentence id on every glyph of that sentence, so a tap
    /// anywhere in the running text resolves to exactly one sentence — the
    /// audio position.
    static let acimSentence = NSAttributedString.Key("acimSentence")
}

/// One page, drawn once and never scrolled.
///
/// The page was measured by `ChapterPaginator` to fit this exact box, so the
/// text ends where the page ends. Colour is applied here rather than during
/// pagination, because the reading position changes many times a second while
/// the page breaks do not.
struct PageTextView: UIViewRepresentable {
    let page: ChapterPaginator.Page
    /// Exactly the box the paginator measured against, so what was measured is
    /// what gets drawn. Without this the text view falls back to its intrinsic
    /// width and the lines run off the page.
    let box: CGSize
    let currentSentenceID: Int
    let currentWordRange: NSRange?
    let fontSize: CGFloat
    let theme: RamsTheme
    let onTap: (Int) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byWordWrapping

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        view.textContainer.size = box

        // A page that holds only the *next* sentence must repaint too, or the
        // lead-in tone would never appear on it.
        let holdsCursor = page.sentenceIDs.contains(currentSentenceID)
            || page.sentenceIDs.contains(currentSentenceID + 1)
        let key = holdsCursor
            ? "c:\(page.chapterID):\(page.id):\(currentSentenceID):\(currentWordRange?.location ?? -1):\(currentWordRange?.length ?? 0):\(fontSize):\(theme.isDark)"
            : "i:\(page.chapterID):\(page.id):\(fontSize):\(theme.isDark)"
        guard key != coordinator.renderedKey else { return }
        coordinator.renderedKey = key
        view.attributedText = coloured()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? box.width, height: proposal.height ?? box.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        var onTap: (Int) -> Void
        var renderedKey = ""
        weak var textView: UITextView?

        init(onTap: @escaping (Int) -> Void) { self.onTap = onTap }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = textView,
                  let text = view.attributedText, text.length > 0,
                  let position = view.closestPosition(to: gesture.location(in: view)) else { return }
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            let index = min(max(0, offset), text.length - 1)
            if let id = text.attribute(.acimSentence, at: index, effectiveRange: nil) as? Int {
                onTap(id)
            }
        }
    }

    /// Four strengths, so the page says where the voice is without shouting:
    /// the text at rest is grey, the sentence coming next leans in, the
    /// sentence being read is full-strength ink, and the single word being
    /// spoken is the only orange on the screen.
    private func coloured() -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: page.text)
        let whole = NSRange(location: 0, length: out.length)
        out.addAttribute(.foregroundColor, value: theme.inkMuted, range: whole)

        let nextSentenceID = currentSentenceID + 1
        var sentenceOnPage: NSRange?
        page.text.enumerateAttribute(.acimSentence, in: whole) { value, range, _ in
            guard let id = value as? Int else { return }
            if id == currentSentenceID {
                out.addAttribute(.foregroundColor, value: theme.ink, range: range)
                // The whole of the sentence that is on this page, not just the
                // first run of it: the marker is clamped into this below.
                sentenceOnPage = sentenceOnPage.map { NSUnionRange($0, range) } ?? range
            } else if id == nextSentenceID {
                out.addAttribute(.foregroundColor, value: theme.inkNext, range: range)
            }
        }

        if let sentence = sentenceOnPage, let word = currentWordRange, word.length > 0 {
            // Word offsets count from the start of the sentence, which is not
            // the start of what is on this page: a sentence running over a page
            // break continues here mid-way. The old code dropped the marker
            // whenever the arithmetic left the string — so on exactly those
            // pages there was no marker at all. Clamp into the part of the
            // sentence that is actually on this page instead; a marker pinned
            // to the visible edge still says where the voice is, nothing says
            // nothing.
            let wanted = NSRange(location: sentence.location + word.location,
                                 length: word.length)
            let lower = max(sentence.location, min(wanted.location, NSMaxRange(sentence) - 1))
            let upper = min(NSMaxRange(sentence), max(NSMaxRange(wanted), lower + 1))

            if upper > lower, upper <= out.length {
                // A marker, not a recoloured word. Orange letters among black
                // ones are easy to miss mid-paragraph; a band of colour laid
                // over the words is seen without being looked for, and reads as
                // one stroke travelling along the line.
                //
                // Background and foreground only: a heavier cut would be wider,
                // which re-breaks the line and makes the paragraph twitch word
                // by word as the marker moves.
                out.addAttributes([.backgroundColor: theme.accent,
                                   .foregroundColor: theme.paper],
                                  range: NSRange(location: lower, length: upper - lower))
            }
        }
        return out
    }
}

/// The card shown after a chapter's last page: turning it starts the next one.
struct ChapterTurnView: View {
    let next: Chapter
    let theme: RamsTheme
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.x(1)) {
            Spacer()
            Text(next.number > 0 ? "\(next.part.displayName) · Chapter \(next.number)" : next.part.displayName)
                .panelLabel(theme)
            Text(next.title)
                .font(.ramsBold(28))
                .foregroundStyle(theme.inkC)
            Rectangle()
                .fill(theme.accentC)
                .frame(width: Grid.x(5), height: 2)
                .padding(.top, Grid.x(2))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
