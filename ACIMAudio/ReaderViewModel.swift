import Foundation
import Combine
import SwiftUI

/// Keeps the *audio* position and the *view* position apart.
///
/// Both are sentence ids; the view layer turns them into pages, because only it
/// knows how big a page is. The rules from the brief:
/// - swiping moves the view only, never the audio
/// - tapping a sentence moves the audio there
/// - play first returns to the page the audio is on
@MainActor
final class ReaderViewModel: ObservableObject {

    let book: ACIMBook
    let audio: AudioReader

    /// The first sentence of the page on screen.
    @Published var viewSentenceID: Int = 0
    /// False while the reader is browsing away from the voice.
    @Published var followingAudio = true

    private var cancellables: Set<AnyCancellable> = []

    init(book: ACIMBook, reader: AudioReader? = nil) {
        self.book = book
        self.audio = reader ?? AudioReader()
        audio.attach(book: book)
        viewSentenceID = audio.currentSentenceID

        // `audio` is a nested ObservableObject, so its changes do not reach this
        // view model's observers by themselves. Republish the slow signals only:
        // the word marker ticks many times a second and the page view observes
        // `audio` directly for it.
        Publishers.Merge3(audio.$isPlaying.map { _ in () },
                          audio.$isPaused.map { _ in () },
                          audio.$isPreparing.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        audio.$currentSentenceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                guard let self else { return }
                self.objectWillChange.send()
                if self.followingAudio, self.viewSentenceID != id {
                    self.viewSentenceID = id
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Derived

    var viewChapterID: Int { book.sentence(withID: viewSentenceID)?.chapterID ?? 0 }
    var audioChapterID: Int { book.sentence(withID: audio.currentSentenceID)?.chapterID ?? 0 }
    var heading: String { book.heading(forSentence: viewSentenceID) }
    var isBrowsing: Bool { !followingAudio }
    var sectionMarks: (index: Int, count: Int) { book.sectionPosition(forSentence: viewSentenceID) }

    /// Where this chapter sits in the book — the rail under the marks.
    var chapterPosition: (index: Int, count: Int) {
        let index = book.chapters.firstIndex { $0.id == viewChapterID } ?? 0
        return (index, max(1, book.chapters.count))
    }

    // MARK: Interactions

    /// The finger moved the page. The audio keeps going wherever it was.
    func browsed(toSentence id: Int, holdsAudio: Bool) {
        viewSentenceID = id
        followingAudio = holdsAudio
    }

    /// A tap in the running text moves the audio to that sentence.
    func tapped(sentenceID: Int) {
        audio.seek(to: sentenceID)
        viewSentenceID = sentenceID
        followingAudio = true
    }

    /// Play returns to the page the audio is on before it resumes.
    func pressedPlay() {
        followingAudio = true
        viewSentenceID = audio.currentSentenceID
        audio.play()
    }

    func pressedPause() { audio.pause() }

    func returnToAudio() {
        followingAudio = true
        viewSentenceID = audio.currentSentenceID
    }

    /// From the chapter overview.
    func jump(toSentence id: Int) {
        audio.seek(to: id)
        viewSentenceID = id
        followingAudio = true
    }

    /// Turning the page past the end of a chapter.
    func openChapter(_ chapter: Chapter) {
        viewSentenceID = chapter.firstSentenceID
        followingAudio = (audio.currentSentenceID == chapter.firstSentenceID)
    }
}
