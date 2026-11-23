import SwiftUI

/// The chapter index, as a continuously driven accordion.
///
/// A `ScrollView` cannot do this honestly: a row's height depends on how far it
/// is from the focus, and the focus was read back from the rows' measured
/// positions — so every height change moved the thing that decided the heights,
/// and the content slid out from under the finger. The earlier version avoided
/// that by freezing the layout until the scroll stopped, which is why it only
/// opened on release.
///
/// Here there is no scroll view and nothing ever scrolls off: the whole book is
/// on screen at once. One continuous value — `position`, in chapter units — is
/// the single source of truth. The focused chapter is open, its neighbours are
/// named, and every other chapter collapses to a rule. The rules then share out
/// whatever height is left, so the index always fills the panel exactly and the
/// accordion opens *while* you drag.
struct ChaptersView: View {
    let book: ACIMBook
    /// The sentence to jump to. Call with Section.firstSentenceID or Chapter.firstSentenceID.
    let onPick: (Int) -> Void
    /// The chapter to open on, so the overview starts where the reader is.
    var startChapterID: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var theme: RamsTheme { RamsTheme.current(scheme) }

    /// Continuous chapter position. 3.0 is chapter index 3 fully open; 3.5 is
    /// half way between three and four, with both half open.
    @State private var position: Double = 0
    @State private var dragAnchor: Double = 0
    @State private var isDragging = false

    /// Finger travel per chapter.
    private static let travelPerChapter: CGFloat = 34
    /// A collapsed rule never gets thinner than this, even in a long book.
    private static let minimumRule: CGFloat = 4
    private static let namedRow: CGFloat = 52

    private var count: Int { max(1, book.chapters.count) }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                accordion(viewport: geo.size, width: geo.size.width)
            }
        }
        .background(theme.paperC.ignoresSafeArea())
        .onAppear {
            let start = book.chapters.firstIndex { $0.id == startChapterID } ?? 0
            position = Double(start)
            dragAnchor = position
        }
    }

    private var header: some View {
        HStack {
            Text("Chapters").font(.ramsMedium(17)).foregroundStyle(theme.inkC)
            Spacer()
            Button("Done") { dismiss() }.panelLabel(theme)
        }
        .padding(.horizontal, Grid.margin)
        .frame(height: Grid.x(7))
        .hairline(theme)
    }

    // MARK: - Layout

    private func accordion(viewport: CGSize, width: CGFloat) -> some View {
        let heights = rowHeights(panel: viewport.height, width: width)

        return VStack(spacing: 0) {
            ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                row(index: index, chapter: chapter, width: width, height: heights[index])
                    .frame(height: heights[index], alignment: .topLeading)
                    .clipped()
            }
        }
        .frame(width: width, height: viewport.height, alignment: .top)
        .contentShape(Rectangle())
        .gesture(scroll)
    }

    /// Every chapter's height, solved so the column fills the panel exactly.
    ///
    /// A row is `rule + namedness·(named − rule) + openness·(open − named)`.
    /// Summing that over all chapters and setting it equal to the panel height
    /// leaves one unknown — the rule height — which falls straight out:
    ///
    ///     rule = (panel − fixed) / Σ(1 − namedness)
    ///
    /// so the collapsed chapters absorb exactly the space the open and named
    /// ones do not take. Nothing is measured and nothing is cut off.
    private func rowHeights(panel: CGFloat, width: CGFloat) -> [CGFloat] {
        var openness: [CGFloat] = []
        var namedness: [CGFloat] = []
        var fixed: CGFloat = 0
        var collapsedWeight: CGFloat = 0

        for (index, chapter) in book.chapters.enumerated() {
            let d = abs(Double(index) - position)
            let o = CGFloat(min(max(1 - d, 0), 1))        // 1 at the focus
            let n = CGFloat(min(max(4 - d, 0), 1))        // 1 within three either side
            openness.append(o)
            namedness.append(n)
            fixed += Self.namedRow * (n - o) + expandedHeight(for: chapter, width: width) * o
            collapsedWeight += (1 - n)
        }

        let rule = collapsedWeight > 0
            ? max(Self.minimumRule, (panel - fixed) / collapsedWeight)
            : Self.minimumRule

        return book.chapters.indices.map { index in
            rule * (1 - namedness[index])
                + Self.namedRow * (namedness[index] - openness[index])
                + expandedHeight(for: book.chapters[index], width: width) * openness[index]
        }
    }

    private var scroll: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragAnchor = position
                }
                position = clamp(dragAnchor - Double(value.translation.height / Self.travelPerChapter))
            }
            .onEnded { value in
                isDragging = false
                // Carry the flick, then come to rest on one chapter.
                let predicted = dragAnchor - Double(value.predictedEndTranslation.height / Self.travelPerChapter)
                let target = clamp(predicted.rounded())
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    position = target
                }
                dragAnchor = target
            }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), Double(count - 1))
    }

    // MARK: - A row

    /// Computed, never measured: the block above, at this width.
    private func expandedHeight(for chapter: Chapter, width: CGFloat) -> CGFloat {
        let tiles = book.sections(ofChapter: chapter.id).filter { !$0.roman.isEmpty }.count
        var total = Grid.x(2) + 13 + Grid.x(1) + 25 + Grid.x(3)   // top, eyebrow, gap, title, bottom
        if tiles > 0 {
            let usable = width - Grid.margin * 2
            let columns = max(1, Int((usable + Grid.x(1)) / (44 + Grid.x(1))))
            let rows = Int(ceil(Double(tiles) / Double(columns)))
            total += Grid.x(1) + CGFloat(rows) * 44 + CGFloat(rows - 1) * Grid.x(1)
        }
        return total
    }

    private func row(index: Int, chapter: Chapter, width: CGFloat, height: CGFloat) -> some View {
        let d = abs(Double(index) - position)
        let openness = min(max(1 - d, 0), 1)
        let namedness = min(max(4 - d, 0), 1)

        // Nothing here is swapped for something else. The rule grows into the
        // selector, and the title is one block throughout — it only gets
        // larger, heavier and paler as its chapter comes into focus.
        return ZStack(alignment: .topLeading) {
            // The rule, grown: full row height, no margins, ink.
            Rectangle()
                .fill(theme.inkC)
                .frame(height: 2 + CGFloat(openness) * (height - 2))
                .padding(.horizontal, Grid.margin * CGFloat(1 - openness))
                .opacity(openness)

            content(chapter, openness: openness)
                .opacity(namedness)

            // The rule as a line, lying over the type. Titles come out from
            // under it; it fades only once the selector has taken its place.
            Rectangle()
                .fill(theme.hairlineC)
                .frame(height: 2)
                .padding(.horizontal, Grid.margin)
                .opacity(1 - openness)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard abs(Double(index) - position) > 0.5 else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                position = Double(index)
            }
            dragAnchor = Double(index)
        }
    }

    /// One block of type for every state. The eyebrow and the tiles grow out of
    /// zero height, and the title itself is a single `Text` whose size, weight
    /// and colour are read straight off `openness`.
    private func content(_ chapter: Chapter, openness: Double) -> some View {
        let tiles = book.sections(ofChapter: chapter.id).filter { !$0.roman.isEmpty }
        let eyebrow = chapter.number == 0
            ? chapter.part.displayName
            : "\(chapter.part.displayName) · Chapter \(chapter.number)"

        return VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(.ramsMedium(10))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(theme.paperC.opacity(0.5))
                .frame(height: 13 * CGFloat(openness), alignment: .bottom)
                .clipped()
                .opacity(openness)

            Button {
                onPick(chapter.firstSentenceID)
                dismiss()
            } label: {
                Text(title(chapter))
                    .font(.custom("HelveticaNeue", size: 16 + 5 * CGFloat(openness))
                            .weight(openness > 0.5 ? .medium : .regular))
                    .foregroundStyle(theme.inkMutedC.mix(with: theme.paperC, by: openness))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .padding(.top, Grid.x(1) * CGFloat(openness))

            if openness > 0.001, !tiles.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: Grid.x(1))],
                          alignment: .leading, spacing: Grid.x(1)) {
                    ForEach(tiles) { section in
                        Button {
                            onPick(section.firstSentenceID)
                            dismiss()
                        } label: {
                            Text(section.roman)
                                .font(.ramsMedium(15))
                                .foregroundStyle(theme.paperC)
                                .frame(width: 44, height: 44)
                                .overlay(Rectangle().stroke(theme.paperC.opacity(0.35), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Grid.x(1))
                .opacity(openness)
            }
        }
        .padding(.top, Grid.x(2))
        .padding(.horizontal, Grid.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ chapter: Chapter) -> String {
        chapter.title.isEmpty ? "\(chapter.part.displayName) \(chapter.number)" : chapter.title
    }
}
