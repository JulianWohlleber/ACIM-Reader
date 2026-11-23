import UIKit

/// Breaks a chapter into pages that actually fit the screen.
///
/// The reader does not scroll: a page holds exactly as much as the viewport can
/// show, so "page 3 of 11" is a real count, not a guess. TextKit does the
/// measuring — the same engine that will draw the text — by laying the chapter
/// out into page-sized containers one after another.
///
/// Pagination is per chapter and cached, because the page counter in the
/// footer is per chapter and because one chapter lays out in a few
/// milliseconds, while the whole book would take many seconds.
@MainActor
final class ChapterPaginator {

    struct Page: Identifiable, Equatable {
        /// Index within its chapter.
        let id: Int
        let chapterID: Int
        let text: NSAttributedString
        let sentenceIDs: [Int]

        var firstSentenceID: Int { sentenceIDs.first ?? 0 }
        var lastSentenceID: Int { sentenceIDs.last ?? firstSentenceID }

        static func == (a: Page, b: Page) -> Bool {
            a.id == b.id && a.chapterID == b.chapterID && a.sentenceIDs == b.sentenceIDs
        }
    }

    private struct Key: Hashable {
        let chapterID: Int
        let width: Int
        let height: Int
        let fontSize: Int
    }

    private var cache: [Key: [Page]] = [:]

    func pages(forChapter chapterID: Int,
               in book: ACIMBook,
               size: CGSize,
               fontSize: CGFloat) -> [Page] {
        guard size.width > 1, size.height > 1 else { return [] }
        let key = Key(chapterID: chapterID,
                      width: Int(size.width.rounded()),
                      height: Int(size.height.rounded()),
                      fontSize: Int(fontSize.rounded()))
        if let cached = cache[key] { return cached }

        let built = layOut(chapterID: chapterID, book: book, size: size, fontSize: fontSize)
        cache[key] = built
        // Geometry rarely changes; keep the cache from growing without bound.
        if cache.count > 24, let oldest = cache.keys.first(where: { $0 != key }) {
            cache.removeValue(forKey: oldest)
        }
        return built
    }

    /// Which page of its chapter a sentence sits on.
    func pageIndex(ofSentence sentenceID: Int, in pages: [Page]) -> Int {
        for page in pages where sentenceID <= page.lastSentenceID {
            if sentenceID >= page.firstSentenceID { return page.id }
            return page.id            // the sentence fell in a gap; use the next page
        }
        return max(0, pages.count - 1)
    }

    // MARK: - Building

    private func layOut(chapterID: Int,
                        book: ACIMBook,
                        size: CGSize,
                        fontSize: CGFloat) -> [Page] {
        guard let chapter = book.chapter(withID: chapterID) else { return [] }

        let full = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.lineSpacing = (fontSize * 0.46).rounded()
        style.paragraphSpacing = (fontSize * 0.95).rounded()
        style.alignment = .natural
        style.hyphenationFactor = 0
        let body = RamsFont.regular(fontSize)

        var lastParagraphID = -1
        for id in chapter.firstSentenceID...chapter.lastSentenceID {
            guard let sentence = book.sentence(withID: id) else { continue }
            // Separators carry no sentence id, so every sentence's run begins
            // exactly at its first character. The word marker is an offset into
            // the sentence, so a stray leading space would shift every word.
            if full.length > 0 {
                let separator = sentence.paragraphID != lastParagraphID ? "\n" : " "
                full.append(NSAttributedString(string: separator, attributes: [
                    .font: body, .paragraphStyle: style
                ]))
            }
            lastParagraphID = sentence.paragraphID

            full.append(NSAttributedString(string: sentence.text, attributes: [
                .font: body,
                .paragraphStyle: style,
                .acimSentence: sentence.id
            ]))
        }
        guard full.length > 0 else { return [] }

        // Lay the chapter into page-sized containers, one after another.
        let storage = NSTextStorage(attributedString: full)
        let manager = NSLayoutManager()
        manager.usesFontLeading = true
        storage.addLayoutManager(manager)

        var pages: [Page] = []
        var consumed = 0
        while consumed < storage.length, pages.count < 400 {
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byWordWrapping
            manager.addTextContainer(container)

            let glyphs = manager.glyphRange(for: container)
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard characters.length > 0 else { break }

            let slice = storage.attributedSubstring(from: characters)
            var ids: [Int] = []
            slice.enumerateAttribute(.acimSentence, in: NSRange(location: 0, length: slice.length)) { value, _, _ in
                if let id = value as? Int, ids.last != id { ids.append(id) }
            }

            pages.append(Page(id: pages.count,
                              chapterID: chapterID,
                              text: slice,
                              sentenceIDs: ids))
            consumed = NSMaxRange(characters)
        }
        return pages
    }
}
