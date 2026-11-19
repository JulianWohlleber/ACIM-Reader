import SwiftUI

struct ReaderScreen: View {
    @StateObject private var viewModel: ReaderViewModel
    @State private var showSettings = false
    @State private var showTOC = false

    @MainActor
    init(book: ACIMBook) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(book: book))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pager
            Divider()
            footer
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(audio: viewModel.audio)
        }
        .sheet(isPresented: $showTOC) {
            TOCView(book: viewModel.book) { chapter in
                showTOC = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    viewModel.jump(toChapter: chapter)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { showTOC = true } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Table of contents")

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.audioChapterTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(viewModel.isBrowsing
                     ? "Browsing — audio continues on page \(viewModel.audioPage + 1)"
                     : viewModel.audioPositionText)
                    .font(.caption)
                    .foregroundStyle(viewModel.isBrowsing ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "speaker.wave.2")
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Pager (page by page reading, swipe left/right to browse)

    private var pager: some View {
        ZStack(alignment: .bottom) {
            CarouselPager(pageCount: viewModel.book.pageCount,
                           page: viewModel.viewPage,
                           didSwipe: { viewModel.swiped(to: $0) }) { pageIndex in
                PageView(book: viewModel.book,
                         pageIndex: pageIndex,
                         audio: viewModel.audio,
                         onTapSentence: { id in viewModel.tapped(sentenceID: id) })
            }

            if viewModel.isBrowsing {
                Button {
                    viewModel.pressedGoToAudio()
                } label: {
                    Label("Back to audio (page \(viewModel.audioPage + 1))",
                          systemImage: "location.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: Footer (transport)

    private var footer: some View {
        HStack(spacing: 28) {
            Button {
                viewModel.audio.stepSentence(forward: false)
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
            }
            .accessibilityLabel("Previous sentence")

            Button {
                if viewModel.audio.isPlaying {
                    viewModel.pressedPause()
                } else {
                    viewModel.pressedPlay()
                }
            } label: {
                Image(systemName: viewModel.audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel(viewModel.audio.isPlaying ? "Pause" : "Play")

            Button {
                viewModel.audio.stepSentence(forward: true)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
            }
            .accessibilityLabel("Next sentence")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .overlay(alignment: .trailing) {
            Text(viewModel.currentPageNumberText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 16)
        }
    }
}
