import Foundation
import NaturalLanguage

/// Parses the plain-text Urtext edition of "A Course in Miracles" (OCR text
/// from archive.org) into the `ACIMBook` model. The parser is deliberately
/// defensive: OCR noise varies, so unknown structures simply become untitled
/// chapters instead of dropping content.
enum ACIMParser {

    private enum RawParagraph {
        case text(String, BookPart)
        case chapterMarker(number: Int, title: String, part: BookPart)
    }

    private static let headingTrim: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: ".:-")
        set.insert(charactersIn: "\u{2013}")   // en dash
        set.insert(charactersIn: "\u{2014}")   // em dash
        return set
    }()

    private static let markerTrim: CharacterSet = {
        var set = CharacterSet.whitespaces
        set.insert(charactersIn: ".:-)")
        set.insert(charactersIn: "\u{2026}")   // ellipsis
        return set
    }()

    // MARK: Entry point

    static func parse(_ raw: String) -> ACIMBook {
        let content = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{c}", with: "\n")     // form feeds
            .replacingOccurrences(of: "-\n", with: "")          // de-hyphenate OCR line breaks

        // Collect logical lines, dropping obvious page furniture.
        var lines: [String] = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // pure page numbers ("12", "273")
            if trimmed.count <= 4,
               trimmed.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil {
                continue
            }
            // table-of-content dot leaders "..... 12"
            if trimmed.contains(".....") { continue }
            lines.append(trimmed)
        }

        // Rebuild the paragraph stream.
        var stream: [RawParagraph] = []
        var buffer: [String] = []
        var currentPart: BookPart = .unknown

        func flush() {
            guard !buffer.isEmpty else { return }
            let joined = buffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { stream.append(.text(joined, currentPart)) }
            buffer.removeAll()
        }

        for line in lines {
            if let marker = classifyHeading(line) {
                flush()
                switch marker {
                case .part(let part): currentPart = part
                case .chapter(let number, let title):
                    stream.append(.chapterMarker(number: number, title: title, part: currentPart))
                }
            } else if line.isEmpty {
                flush()
            } else {
                buffer.append(line)
            }
        }
        flush()

        var hasChapter = false
        for entry in stream {
            if case .chapterMarker = entry { hasChapter = true; break }
        }
        if !hasChapter && stream.isEmpty == false {
            return build(stream: stream, forceSingleChapter: true)
        }
        return build(stream: stream, forceSingleChapter: false)
    }

    // MARK: Heading detection

    private enum HeadingMarker {
        case part(BookPart)
        case chapter(number: Int, title: String)
    }

    private static func classifyHeading(_ line: String) -> HeadingMarker? {
        let compact = line.uppercased().replacingOccurrences(of: " ", with: "")

        if compact == "TEXT" || compact == "TEXTBOOK" || compact == "THETEXT" { return .part(.text) }
        if compact.hasPrefix("WORKBOOK"), compact.count <= 40 { return .part(.workbook) }
        if compact.hasPrefix("MANUAL"), compact.count <= 40 { return .part(.manual) }

        // "CHAPTER 5" / "Chapter 5: Perceived versus Known"
        if line.uppercased().hasPrefix("CHAPTER") {
            let rest = line.dropFirst("CHAPTER".count).trimmingCharacters(in: .whitespaces)
            let digits = rest.prefix { $0.isNumber }
            if !digits.isEmpty {
                let number = Int(digits) ?? 0
                var remainder = String(rest.dropFirst(digits.count))
                while let f = remainder.first, f.unicodeScalars.allSatisfy(markerTrim.contains) { remainder.removeFirst() }
                let title = cleanTitle(remainder)
                return .chapter(number: number, title: title)
            }
            return nil // bare "CHAPTER", title follows on the next line
        }

        // "LESSON 42" / "Lesson 42." (workbook)
        if line.uppercased().hasPrefix("LESSON") {
            let rest = line.dropFirst("LESSON".count).trimmingCharacters(in: .whitespaces)
            let digits = rest.prefix { $0.isNumber }
            if !digits.isEmpty {
                let number = Int(digits) ?? 0
                var remainder = String(rest.dropFirst(digits.count))
                while let f = remainder.first, f.unicodeScalars.allSatisfy(markerTrim.contains) { remainder.removeFirst() }
                let title = cleanTitle(remainder)
                return .chapter(number: number, title: title)
            }
        }

        // "1. The Meaning of Miracles" style, only for short heading-like lines
        if line.count <= 70, line.first?.isNumber == true,
           line.dropFirst().prefix(2) == ". " {
            let num = line.prefix { $0.isNumber }
            let title = cleanTitle(String(line.dropFirst(num.count + 2)))
            return .chapter(number: Int(num) ?? 0, title: title)
        }

        return nil
    }

    private static func cleanTitle(_ t: String) -> String {
        let trimmed = t.trimmingCharacters(in: headingTrim)
        return String(trimmed.prefix(90)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Book assembly

    private struct OpenChapter {
        var part: BookPart
        var number: Int
        var title: String
        var firstSentenceID: Int
    }

    private static func build(stream: [RawParagraph], forceSingleChapter: Bool) -> ACIMBook {
        var sentences: [Sentence] = []

        func appendParagraph(_ text: String, chapterID: Int, into paragraphs: inout [Paragraph]) {
            let pieces = splitIntoSentences(text)
            guard !pieces.isEmpty else { return }
            let paragraphID = paragraphs.count
            var ids: [Int] = []
            for piece in pieces {
                let id = sentences.count
                sentences.append(Sentence(id: id, chapterID: chapterID, paragraphID: paragraphID, text: piece))
                ids.append(id)
            }
            paragraphs.append(Paragraph(id: paragraphID, chapterID: chapterID, sentenceIDs: ids))
        }

        var paragraphModels: [Paragraph] = []

        // --- single-chapter fallback: keep the book readable whatever happens
        if forceSingleChapter {
            for entry in stream {
                if case .text(let text, _) = entry {
                    appendParagraph(text, chapterID: 1, into: &paragraphModels)
                }
            }
            let chapter = Chapter(id: 1, part: .unknown, number: 0, title: "A Course in Miracles",
                                  firstSentenceID: 0, lastSentenceID: max(0, sentences.count - 1))
            return ACIMBook(sentences: sentences, paragraphs: paragraphModels, chapters: [chapter])
        }

        // --- structured build
        var openChapter = OpenChapter(part: .text, number: 0, title: "", firstSentenceID: 0)
        var closed: [OpenChapter] = []
        var currentChapterID = 1

        for entry in stream {
            switch entry {
            case .chapterMarker(let number, let title, let part):
                closed.append(openChapter)
                currentChapterID += 1
                var effectivePart = part
                if effectivePart == .unknown, let last = closed.last {
                    effectivePart = last.part
                }
                openChapter = OpenChapter(part: effectivePart, number: number,
                                          title: title, firstSentenceID: sentences.count)

            case .text(let text, let part):
                // Carry part changes that arrive between chapter markers.
                if openChapter.title.isEmpty && openChapter.number == 0
                    && openChapter.firstSentenceID == sentences.count, part != .unknown {
                    openChapter.part = part
                }
                appendParagraph(text, chapterID: currentChapterID, into: &paragraphModels)
            }
        }
        closed.append(openChapter)

        // Assemble final chapters with correct end indices.
        var chapters: [Chapter] = []
        for (i, stub) in closed.enumerated() {
            let last = sentences.count - 1
            let start = min(stub.firstSentenceID, max(0, last))
            var end = last
            if i + 1 < closed.count {
                end = max(start, closed[i + 1].firstSentenceID - 1)
            }
            end = min(end, last)
            if start <= end {
                chapters.append(Chapter(id: i + 1, part: stub.part, number: stub.number,
                                        title: stub.title, firstSentenceID: start, lastSentenceID: end))
            } else {
                chapters.append(Chapter(id: i + 1, part: stub.part, number: stub.number,
                                        title: stub.title, firstSentenceID: end, lastSentenceID: end))
            }
        }

        if chapters.isEmpty {
            chapters = [Chapter(id: 1, part: .unknown, number: 0, title: "A Course in Miracles",
                                firstSentenceID: 0, lastSentenceID: max(0, sentences.count - 1))]
        }
        return ACIMBook(sentences: sentences, paragraphs: paragraphModels, chapters: chapters)
    }

    // MARK: Sentence splitting

    /// Sentence segmentation using Apple's `NLTokenizer`, which handles
    /// abbreviations, decimals and quotes far better than a naive regex.
    static func splitIntoSentences(_ text: String) -> [String] {
        var results: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let trimmed = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 1 { results.append(trimmed) }
            return true
        }
        if results.isEmpty {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { results = [t] }
        }
        return results
    }
}
