import SwiftUI

/// The reading screen.
///
/// One line of heading, the page, and a control strip. Nothing else: no
/// contents button (the heading opens the chapters), no sentence counter (the
/// marks in the strip say where you are), no title block. Pressing play is what
/// brings you back to the voice, so there is no "back" control either.
struct ReaderScreen: View {
    @StateObject private var viewModel: ReaderViewModel
    @State private var paginator = ChapterPaginator()
    @State private var showVoices = false
    @State private var showChapters = false
    /// True while the page turned past a chapter's last page.
    @State private var onChapterTurn = false

    @Environment(\.colorScheme) private var scheme
    @AppStorage("readerFontSize") private var fontSize: Double = 19

    private var theme: RamsTheme { RamsTheme.current(scheme) }
    private var book: ACIMBook { viewModel.book }

    private let headerHeight = Grid.x(9)
    private let footerHeight = Grid.x(9)

    @MainActor
    init(book: ACIMBook) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(book: book))
    }

    var body: some View {
        GeometryReader { geo in
            // The strip is a panel on the front of the device: it runs past the
            // home indicator to the physical edge, and its contents sit above it.
            let bottomInset = geo.safeAreaInsets.bottom
            let box = CGSize(
                width: max(1, geo.size.width - Grid.margin * 2),
                height: max(1, geo.size.height - headerHeight - footerHeight - bottomInset - Grid.x(4))
            )
            let pages = paginator.pages(forChapter: viewModel.viewChapterID,
                                        in: book, size: box, fontSize: CGFloat(fontSize))
            let pageIndex = paginator.pageIndex(ofSentence: viewModel.viewSentenceID, in: pages)
            let nextChapter = book.chapter(withID: viewModel.viewChapterID + 1)

            VStack(spacing: 0) {
                header
                    .frame(height: headerHeight)
                    .hairline(theme)

                pager(pages: pages, pageIndex: pageIndex, nextChapter: nextChapter, box: box)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer(pageIndex: pageIndex,
                       pageCount: max(1, pages.count),
                       bottomInset: bottomInset)
                    .frame(height: footerHeight + bottomInset)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(theme.paperC.ignoresSafeArea())
        .onChange(of: viewModel.viewChapterID) { _, _ in onChapterTurn = false }
        .sheet(isPresented: $showVoices) {
            SettingsView(audio: viewModel.audio)
        }
        .sheet(isPresented: $showChapters) {
            ChaptersView(book: book,
                         onPick: { viewModel.jump(toSentence: $0) },
                         startChapterID: viewModel.viewChapterID)
        }
    }

    // MARK: - Heading

    private var header: some View {
        VStack(alignment: .leading, spacing: Grid.x(1)) {
            HStack(alignment: .top) {
                // The way into the chapters. It used to be the heading text
                // alone: a bare `Text` in a plain button owns only its glyphs,
                // so a tap a few points high, low or past the last letter fell
                // through and nothing happened. Now the control carries a
                // label that names it, a mark that says it opens, and a box
                // big enough to hit.
                Button { showChapters = true } label: {
                    VStack(alignment: .leading, spacing: Grid.x(0.5)) {
                        Text("Chapters").panelLabel(theme)
                        HStack(spacing: Grid.x(1)) {
                            Text(viewModel.heading)
                                .font(.ramsMedium(16))
                                .foregroundStyle(theme.inkC)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            DisclosureMark(theme: theme)
                        }
                    }
                    .padding(.vertical, Grid.x(1))
                    .padding(.trailing, Grid.x(1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: Grid.x(2))

                Button { showVoices = true } label: {
                    Text("Voice")
                        .panelLabel(theme)
                        .padding(.vertical, Grid.x(1))
                        .padding(.leading, Grid.x(2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(theme.accentC)
                .frame(width: Grid.x(4), height: 2)
        }
        .padding(.horizontal, Grid.margin)
        .padding(.top, Grid.x(1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The page

    private func pager(pages: [ChapterPaginator.Page],
                       pageIndex: Int,
                       nextChapter: Chapter?,
                       box: CGSize) -> some View {
        let total = pages.count + (nextChapter != nil ? 1 : 0)
        let shown = onChapterTurn ? pages.count : pageIndex

        return CarouselPager(pageCount: max(1, total), page: shown) { index in
            if index < pages.count {
                onChapterTurn = false
                let page = pages[index]
                viewModel.browsed(toSentence: page.firstSentenceID,
                                  holdsAudio: page.sentenceIDs.contains(viewModel.audio.currentSentenceID))
            } else {
                onChapterTurn = true
            }
        } makePage: { index in
            Group {
                if index < pages.count {
                    PageTextView(page: pages[index],
                                 box: box,
                                 currentSentenceID: viewModel.audio.currentSentenceID,
                                 currentWordRange: viewModel.audio.currentWordRange,
                                 fontSize: CGFloat(fontSize),
                                 theme: theme,
                                 onTap: { viewModel.tapped(sentenceID: $0) })
                        .frame(width: box.width, height: box.height, alignment: .topLeading)
                } else if let nextChapter {
                    ChapterTurnView(next: nextChapter, theme: theme) {
                        viewModel.openChapter(nextChapter)
                    }
                    .frame(width: box.width, height: box.height)
                }
            }
            .padding(.horizontal, Grid.margin)
            .padding(.top, Grid.x(2))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Control strip

    private func footer(pageIndex: Int, pageCount: Int, bottomInset: CGFloat) -> some View {
        let marks = viewModel.sectionMarks
        let place = viewModel.chapterPosition

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Grid.x(1.25)) {
                Text("Page \(min(pageIndex, pageCount - 1) + 1) of \(pageCount)")
                    .panelLabel(theme)

                // One mark per sub-chapter, filled up to where you are.
                HStack(spacing: Grid.x(0.75)) {
                    ForEach(0..<marks.count, id: \.self) { index in
                        Circle()
                            .fill(index <= marks.index ? theme.inkC : theme.hairlineC)
                            .frame(width: 6, height: 6)
                    }
                }

                // And where this chapter sits in the whole book.
                GeometryReader { rail in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(theme.hairlineC)
                        Rectangle()
                            .fill(theme.inkC)
                            .frame(width: max(2, rail.size.width
                                   * CGFloat(place.index + 1) / CGFloat(place.count)))
                    }
                }
                .frame(height: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Grid.margin)
            .padding(.bottom, bottomInset)
            .frame(maxHeight: .infinity)
            .background(theme.surfaceC)

            Button {
                if viewModel.audio.isPlaying { viewModel.pressedPause() }
                else { viewModel.pressedPlay() }
            } label: {
                Group {
                    if viewModel.audio.isPreparing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(theme.paperC)
                    } else {
                        Image(systemName: viewModel.audio.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(theme.paperC)
                    }
                }
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Orange invites the press; while the voice actually speaks the
                // block goes quiet and black, and the orange belongs to the word.
                .background(viewModel.audio.isPlaying ? theme.inkC : theme.accentC)
            }
            .buttonStyle(.plain)
            .frame(width: Grid.x(10))
            .accessibilityLabel(viewModel.audio.isPlaying ? "Pause" : "Play")
        }
        .hairline(theme, edge: .top)
    }
}

/// The mark that says a heading opens something.
///
/// A downward triangle: the same figure the app icon is built from, pointing
/// the way the panel arrives. Small and in the signal colour, because it is
/// the only thing on the page asking to be pressed.
private struct DisclosureMark: View {
    let theme: RamsTheme

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 10, y: 0))
            path.addLine(to: CGPoint(x: 5, y: 6))
            path.closeSubpath()
        }
        .fill(theme.accentC)
        .frame(width: 10, height: 6)
        .accessibilityHidden(true)
    }
}
