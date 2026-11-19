import Foundation
import Combine
import SwiftUI

/// Glues the book, the audio position and the *view* position together.
///
/// The three interactions from the spec map to states like this:
/// - **Swipe left/right** changes `viewPage` only. If you swipe away from the
///   audio, `isBrowsing` becomes true and a pill offers to jump back. Audio
///   playback is never interrupted.
/// - **Tap on a sentence** moves the audio position there and (if it was
///   playing/paused) continues playback from it.
/// - **Play** while browsing first snaps the view back to the audio page,
///   then plays/resumes.
@MainActor
final class ReaderViewModel: ObservableObject {

    let book: ACIMBook
    let audio: AudioReader

    /// The page currently visible to the user.
    @Published var viewPage: Int = 0
    /// True when the view follows the audio position (not browsing).
    @Published var followingAudio = true

    private var cancellables: Set<AnyCancellable> = []

    init(book: ACIMBook, audio: AudioReader = AudioReader()) {
        self.book = book
        self.audio = audio
        audio.attach(book: book)
        viewPage = book.page(ofSentence: audio.currentSentenceID)

        // Follow the audio position while in follow-mode.
        audio.$currentSentenceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                guard let self else { return }
                if self.followingAudio {
                    let page = self.book.page(ofSentence: id)
                    if page != self.viewPage {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            self.viewPage = page
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Derived state

    var audioPage: Int { book.page(ofSentence: audio.currentSentenceID) }
    var isBrowsing: Bool { viewPage != audioPage }

    var currentPageNumberText: String {
        "Page \(viewPage + 1) of \(book.pageCount)"
    }

    var audioChapterTitle: String {
        book.title(forSentence: audio.currentSentenceID)
    }

    var audioPositionText: String {
        "Sentence \(audio.currentSentenceID + 1) of \(book.sentenceCount)"
    }

    // MARK: Interactions

    /// Called by the pager when the user swiped to another page.
    func swiped(to page: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            viewPage = page
        }
        followingAudio = (page == audioPage)
    }

    /// Called by the settings button etc. when nothing structural changes.
    func reactivateFollow() {
        followingAudio = true
    }

    /// Tap on a sentence: move the audio there.
    func tapped(sentenceID: Int) {
        audio.seek(to: sentenceID)
        followingAudio = true
        let page = book.page(ofSentence: audio.currentSentenceID)
        if page != viewPage {
            withAnimation(.easeInOut(duration: 0.25)) { viewPage = page }
        }
        objectWillChange.send()
    }

    /// The play button. If the user browsed away, we first bring the view
    /// back to the page where the audio is, then resume playback.
    func pressedPlay() {
        if isBrowsing {
            followingAudio = true
            withAnimation(.easeInOut(duration: 0.25)) {
                viewPage = audioPage
            }
        }
        audio.play()
    }

    func pressedPause() {
        audio.pause()
    }

    /// The "back to audio" pill: jump the *view* back without touching
    /// the audio itself.
    func pressedGoToAudio() {
        followingAudio = true
        withAnimation(.easeInOut(duration: 0.25)) {
            viewPage = audioPage
        }
    }

    /// Jump to the start of a chapter (table of contents).
    func jump(toChapter chapter: Chapter) {
        tapped(sentenceID: chapter.firstSentenceID)
    }
}
