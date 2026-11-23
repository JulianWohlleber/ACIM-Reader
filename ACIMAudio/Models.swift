import Foundation

// MARK: - Core model

/// A single sentence. The `id` is the global (book-wide) index and doubles as
/// the audio position: the audio engine always knows which sentence it speaks,
/// the reader always knows which sentence is on which page.
struct Sentence: Codable, Identifiable, Equatable, Hashable {
    let id: Int          // global index across the whole book
    let chapterID: Int
    let sectionID: Int   // global index into `ACIMBook.sections`
    let paragraphID: Int
    let text: String

    init(id: Int, chapterID: Int, sectionID: Int = 0, paragraphID: Int, text: String) {
        self.id = id
        self.chapterID = chapterID
        self.sectionID = sectionID
        self.paragraphID = paragraphID
        self.text = text
    }
}

/// A sub-chapter. In the Text these are the numbered sections printed as
/// "I. Principles of Miracles"; a Workbook lesson or a Manual section has a
/// single unnamed one. The reader cites a position the way the Course itself
/// is cited: chapter and section, as in 3.III.
struct Section: Codable, Identifiable, Equatable {
    let id: Int          // global index across the whole book
    let chapterID: Int
    let number: Int      // 1-based position within its chapter
    let roman: String    // "III", or "" when the source prints no heading
    let title: String
    let firstSentenceID: Int
    let lastSentenceID: Int  // inclusive
}

/// A paragraph bundles consecutive sentences that belong together visually.
struct Paragraph: Codable, Identifiable, Equatable {
    let id: Int
    let chapterID: Int
    let sentenceIDs: [Int]

    var firstSentenceID: Int { sentenceIDs.first ?? 0 }
}

enum BookPart: String, Codable, CaseIterable {
    case text
    case workbook
    case manual
    case unknown

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .workbook: return "Workbook"
        case .manual: return "Manual"
        case .unknown: return "Book"
        }
    }
}

/// A chapter of the book (Text chapter, workbook lesson, manual section...).
struct Chapter: Codable, Identifiable, Equatable {
    let id: Int
    let part: BookPart
    let number: Int      // chapter / lesson number, 0 when untitled
    let title: String
    let firstSentenceID: Int
    let lastSentenceID: Int  // inclusive

    var range: Range<Int> { firstSentenceID..<max(firstSentenceID, lastSentenceID + 1) }
}

// MARK: - Book

/// The parsed, page-less book. Pages are derived on demand so that future
/// font-size changes never invalidate the stored model.
struct ACIMBook: Codable, Equatable {
    let sentences: [Sentence]
    let paragraphs: [Paragraph]
    let chapters: [Chapter]
    let sections: [Section]

    init(sentences: [Sentence],
         paragraphs: [Paragraph],
         chapters: [Chapter],
         sections: [Section] = []) {
        self.sentences = sentences
        self.paragraphs = paragraphs
        self.chapters = chapters
        self.sections = sections
    }

    /// A "page" is a fixed-size window over the global sentence list.
    static let sentencesPerPage = 20

    var sentenceCount: Int { sentences.count }
    var pageCount: Int { max(1, Int(ceil(Double(sentences.count) / Double(Self.sentencesPerPage)))) }

    func page(ofSentence id: Int) -> Int {
        min(max(0, id / Self.sentencesPerPage), pageCount - 1)
    }

    func sentenceIDs(onPage page: Int) -> Range<Int> {
        let start = page * Self.sentencesPerPage
        let end = min(start + Self.sentencesPerPage, sentences.count)
        return start..<max(start, end)
    }

    func sentence(withID id: Int) -> Sentence? {
        guard sentences.indices.contains(id) else { return nil }
        return sentences[id]
    }

    /// Chapter of a global sentence id (uses an index built in `indexByID`).
    func chapterID(ofSentence id: Int) -> Int? {
        sentence(withID: id)?.chapterID
    }

    func chapter(withID id: Int) -> Chapter? {
        chapters.first { $0.id == id }
    }

    func title(forSentence id: Int) -> String {
        guard let cID = chapterID(ofSentence: id), let c = chapter(withID: cID) else { return "" }
        if c.number > 0 { return "\(c.part.displayName) · \(c.title.isEmpty ? String(c.number) : c.title)" }
        return c.title
    }

    func section(withID id: Int) -> Section? {
        guard sections.indices.contains(id) else { return nil }
        return sections[id]
    }

    func sections(ofChapter chapterID: Int) -> [Section] {
        sections.filter { $0.chapterID == chapterID }
    }

    /// How the Course cites itself: chapter and section, plus how many sections
    /// that chapter has — "3.III / 3.VI". Lessons and Manual sections have no
    /// sub-headings, so they are named instead.
    func reference(forSentence id: Int) -> String {
        guard let sentence = sentence(withID: id),
              let chapter = chapter(withID: sentence.chapterID) else { return "" }

        switch chapter.part {
        case .text:
            guard let here = section(withID: sentence.sectionID), !here.roman.isEmpty,
                  let last = sections(ofChapter: chapter.id).last, !last.roman.isEmpty
            else { return chapter.title }
            return "\(chapter.number).\(here.roman) / \(chapter.number).\(last.roman)"

        case .workbook:
            return chapter.number > 0 ? "Lesson \(chapter.number)" : chapter.title

        case .manual:
            return chapter.number > 0 ? "Manual \(chapter.number)" : chapter.title

        case .unknown:
            return chapter.title
        }
    }

    /// The one line the reader shows: the Course's own citation plus the
    /// chapter's name — "3.I · The Innocent Perception", or just "Introduction"
    /// where the source prints no section.
    func heading(forSentence id: Int) -> String {
        guard let sentence = sentence(withID: id),
              let chapter = chapter(withID: sentence.chapterID) else { return "" }

        switch chapter.part {
        case .text:
            if let here = section(withID: sentence.sectionID), !here.roman.isEmpty {
                return "\(chapter.number).\(here.roman) · \(chapter.title)"
            }
            return chapter.title
        case .workbook:
            return chapter.number > 0 ? "Lesson \(chapter.number)" : chapter.title
        case .manual:
            return chapter.number > 0 ? "Manual \(chapter.number) · \(chapter.title)" : chapter.title
        case .unknown:
            return chapter.title
        }
    }

    /// Which sub-chapter of its chapter a sentence is in, and how many there
    /// are — the footer draws one mark per sub-chapter.
    func sectionPosition(forSentence id: Int) -> (index: Int, count: Int) {
        guard let sentence = sentence(withID: id) else { return (0, 1) }
        let inChapter = sections(ofChapter: sentence.chapterID)
        guard !inChapter.isEmpty else { return (0, 1) }
        let index = inChapter.firstIndex { $0.id == sentence.sectionID } ?? 0
        return (index, inChapter.count)
    }

    enum CodingKeys: String, CodingKey {
        case sentences, paragraphs, chapters, sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentences  = try container.decode([Sentence].self, forKey: .sentences)
        paragraphs = try container.decode([Paragraph].self, forKey: .paragraphs)
        chapters   = try container.decode([Chapter].self, forKey: .chapters)
        sections   = try container.decodeIfPresent([Section].self, forKey: .sections) ?? []
    }
}
