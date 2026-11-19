import SwiftUI

/// A three-slot page carousel: exactly the previous, current and next page
/// exist at any time, so even a 1000+ page book stays cheap.
struct CarouselPager<Page: View>: View {
    let pageCount: Int
    let page: Int
    let didSwipe: (Int) -> Void
    @ViewBuilder let makePage: (Int) -> Page

    /// 0 = previous slot, 1 = visible slot, 2 = next slot.
    @State private var slot = 1

    var body: some View {
        Group {
            if pageCount <= 1 {
                makePage(page)
            } else {
                TabView(selection: $slot) {
                    makePage(neighbour(-1)).tag(0)
                    makePage(page).tag(1)
                    makePage(neighbour(+1)).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: slot) { _, new in
                    guard new != 1 else { return }
                    handleSwipe(new)
                }
            }
        }
    }

    private func neighbour(_ delta: Int) -> Int {
        min(max(page + delta, 0), pageCount - 1)
    }

    private func handleSwipe(_ new: Int) {
        let target = min(max(page + (new == 2 ? 1 : -1), 0), pageCount - 1)
        let unchanged = (new == 2 && target == page && page == pageCount - 1)
            || (new == 0 && target == page && page == 0)
        // snap back to the middle slot without animating
        slot = 1
        if unchanged {
            return // tried to swipe past the first/last page
        }
        didSwipe(target)
    }
}
