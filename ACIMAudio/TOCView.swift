import SwiftUI

/// Table of contents: jump anywhere in the book.
struct TOCView: View {
    let book: ACIMBook
    let onPick: (Chapter) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(book.chapters, id: \.id) { chapter in
                Button {
                    onPick(chapter)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayTitle(chapter))
                            .font(.body.weight(chapter.number == 0 ? .regular : .medium))
                            .foregroundStyle(.primary)
                        Text(chapter.part.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func displayTitle(_ chapter: Chapter) -> String {
        if !chapter.title.isEmpty { return chapter.title }
        if chapter.number > 0 {
            switch chapter.part {
            case .workbook: return "Lesson \(chapter.number)"
            case .manual: return "Section \(chapter.number)"
            default: return "Chapter \(chapter.number)"
            }
        }
        return "Untitled"
    }
}
