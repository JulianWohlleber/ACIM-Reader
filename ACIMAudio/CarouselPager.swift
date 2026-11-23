import SwiftUI

/// Horizontal page browsing.
///
/// This used to be a three-slot `TabView` that snapped itself back to the
/// middle after every swipe. Resetting the slot while the transition was still
/// animating raced with the page change, so one flick could advance two pages.
///
/// Instead this is one paging scroll view over a lazy row of all pages: the
/// system does the paging, `scrollPosition` is the single source of truth, and
/// only the pages near the viewport are ever built — a 2000-page book stays
/// cheap. Browsing here never touches the audio position; that is the whole
/// point of the gesture.
struct CarouselPager<Page: View>: View {
    let pageCount: Int
    let page: Int
    let didSwipe: (Int) -> Void
    @ViewBuilder let makePage: (Int) -> Page

    @State private var position: Int?

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<max(pageCount, 1), id: \.self) { index in
                        makePage(index)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position, anchor: .center)
            .scrollIndicators(.hidden)
            .onAppear { position = page }
            // Driven from outside: follow-the-audio, the contents list,
            // "back to page N".
            .onChange(of: page) { _, newPage in
                guard position != newPage else { return }
                withAnimation(.easeInOut(duration: 0.3)) { position = newPage }
            }
            // Driven by the finger.
            .onChange(of: position) { _, newPosition in
                guard let newPosition, newPosition != page else { return }
                didSwipe(newPosition)
            }
        }
    }
}
