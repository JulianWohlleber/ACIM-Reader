import Foundation

/// The structured corpus shipped inside the app.
///
/// Built at development time by `Tools/build_corpus.py` from the English
/// Wikisource transcription of the 1975 first edition, which Wikisource carries
/// under {{PD-US-no-notice}}: the work was distributed without a copyright
/// notice before publication, and the 1975 registration was invalidated in
/// *Penguin Books USA v. New Christian Church of Full Endeavor*,
/// 288 F. Supp. 2d 544 (S.D.N.Y. 2003).
///
/// Shipping it rather than downloading an OCR scan at runtime means the reader
/// opens instantly, works offline, and shows the work itself instead of a
/// scanner's front matter.
struct Corpus: Decodable {
    /// A sub-chapter as the source prints it.
    struct SectionNode: Decodable {
        let number: Int
        let roman: String
        let title: String
        let paragraphs: [String]
    }

    struct ChapterNode: Decodable {
        let part: String
        let number: Int
        let title: String
        let sections: [SectionNode]
    }

    let edition: String
    let source: String
    let license: String
    let chapters: [ChapterNode]
}

enum CorpusBuilder {

    static var bundledURL: URL? {
        Bundle.main.url(forResource: "acim", withExtension: "json")
    }

    /// Turn the structured corpus into the flat model the reader and the audio
    /// engine share. Sentences are split with Apple's `NLTokenizer`, which
    /// handles abbreviations and quotations better than any rule we would write.
    static func build(from data: Data) throws -> ACIMBook {
        let corpus = try JSONDecoder().decode(Corpus.self, from: data)

        var sentences: [Sentence] = []
        var paragraphs: [Paragraph] = []
        var sections: [Section] = []
        var chapters: [Chapter] = []

        for (chapterIndex, chapter) in corpus.chapters.enumerated() {
            let chapterFirstSentence = sentences.count

            for section in chapter.sections {
                let sectionID = sections.count
                let sectionFirstSentence = sentences.count

                for paragraphText in section.paragraphs {
                    let paragraphID = paragraphs.count
                    var ids: [Int] = []

                    for text in ACIMParser.splitIntoSentences(paragraphText) {
                        let id = sentences.count
                        sentences.append(Sentence(id: id,
                                                  chapterID: chapterIndex,
                                                  sectionID: sectionID,
                                                  paragraphID: paragraphID,
                                                  text: text))
                        ids.append(id)
                    }

                    guard !ids.isEmpty else { continue }
                    paragraphs.append(Paragraph(id: paragraphID,
                                                chapterID: chapterIndex,
                                                sentenceIDs: ids))
                }

                let sectionLastSentence = sentences.count - 1
                guard sectionLastSentence >= sectionFirstSentence else { continue }

                sections.append(Section(id: sectionID,
                                        chapterID: chapterIndex,
                                        number: section.number,
                                        roman: section.roman,
                                        title: section.title,
                                        firstSentenceID: sectionFirstSentence,
                                        lastSentenceID: sectionLastSentence))
            }

            let chapterLastSentence = sentences.count - 1
            guard chapterLastSentence >= chapterFirstSentence else { continue }

            chapters.append(Chapter(id: chapterIndex,
                                    part: BookPart(rawValue: chapter.part) ?? .unknown,
                                    number: chapter.number,
                                    title: chapter.title,
                                    firstSentenceID: chapterFirstSentence,
                                    lastSentenceID: chapterLastSentence))
        }

        return ACIMBook(sentences: sentences,
                        paragraphs: paragraphs,
                        chapters: chapters,
                        sections: sections)
    }
}
