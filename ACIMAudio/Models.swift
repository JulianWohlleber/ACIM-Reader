import Foundation

// MARK: - Core model

/// A single sentence. The `id` is the global (book-wide) index and doubles as
/// the audio position: the audio engine always knows which sentence it speaks,
/// the reader always knows which sentence is on which page.
struct Sentence: Codable, Identifiable, Equatable, Hashable {
    let id: Int          // global index across the whole book
    let chapterID: Int
    let paragraphID: Int
    let text: String
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

    enum CodingKeys: String, CodingKey {
        case sentences, paragraphs, chapters
    }
}
