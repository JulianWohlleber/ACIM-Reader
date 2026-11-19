import SwiftUI

/// One "page": all sentences of the page, grouped back into their
/// paragraphs, each sentence individually tappable and individually
/// highlightable while it is being spoken.
struct PageView: View {
    let book: ACIMBook
    let pageIndex: Int
    @ObservedObject var audio: AudioReader
    let onTapSentence: (Int) -> Void

    private struct ParagraphGroup: Identifiable {
        let id: Int          // paragraph id
        let sentences: [Sentence]
    }

    /// Paragraphs that have at least one sentence on this page,
    /// in reading order, with the subset of sentences shown.
    private var visibleParagraphs: [ParagraphGroup] {
        let ids = book.sentenceIDs(onPage: pageIndex)
        guard ids.count > 0 else { return [] }
        var groups: [ParagraphGroup] = []
        var currentID: Int? = nil
        var currentSentences: [Sentence] = []
        func finalize() {
            if let cid = currentID, !currentSentences.isEmpty {
                groups.append(ParagraphGroup(id: cid, sentences: currentSentences))
            }
            currentID = nil
            currentSentences = []
        }
        for id in ids {
            guard let sentence = book.sentence(withID: id) else { continue }
            if sentence.paragraphID == currentID, book.paragraphs.indices.contains(sentence.paragraphID) {
                currentSentences.append(sentence)
            } else {
                finalize()
                if book.paragraphs.indices.contains(sentence.paragraphID) {
                    currentID = sentence.paragraphID
                    currentSentences = [sentence]
                }
            }
        }
        finalize()
        return groups
    }

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 18) {
                    if pageIndex == 0 {
                        titleBlock
                    }
                    ForEach(visibleParagraphs) { group in
                        ParagraphFlowView(sentences: group.sentences,
                                          currentSentenceID: audio.currentSentenceID,
                                          currentWordRange: audio.currentWordRange,
                                          onTap: onTapSentence)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("page-\(pageIndex)")
                .onChange(of: audio.currentSentenceID) { _, newValue in
                    if book.page(ofSentence: newValue) == pageIndex {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("sentence-\(newValue)", anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("A Course in Miracles")
                .font(.title2.bold())
            Text("Urtext Edition · read aloud")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }
}

/// A paragraph rendered as a flow of sentence chips.
private struct ParagraphFlowView: View {
    let sentences: [Sentence]
    let currentSentenceID: Int
    let currentWordRange: NSRange?
    let onTap: (Int) -> Void

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(sentences) { sentence in
                SentenceView(sentence: sentence,
                             isCurrent: sentence.id == currentSentenceID,
                             wordRange: sentence.id == currentSentenceID ? currentWordRange : nil)
                    .onTapGesture { onTap(sentence.id) }
            }
        }
    }
}

/// One sentence. Three visual states:
/// - normal book text
/// - current sentence: soft accent background
/// - while spoken: the active word is tinted
struct SentenceView: View {
    let sentence: Sentence
    let isCurrent: Bool
    let wordRange: NSRange?

    var body: some View {
        Group {
            if isCurrent, let wordRange, wordRange.length > 0,
               let range = Range(wordRange, in: sentence.text),
               range.upperBound <= sentence.text.endIndex,
               range.lowerBound < range.upperBound {
                (Text(String(sentence.text[..<range.lowerBound]))
                 + Text(String(sentence.text[range])).foregroundColor(.accentColor).weight(.bold)
                 + Text(String(sentence.text[range.upperBound...])))
                    .font(.body)
            } else {
                Text(sentence.text)
                    .font(.body)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .id("sentence-\(sentence.id)")
        .opacity(isCurrent ? 1 : 0.86)
    }
}
