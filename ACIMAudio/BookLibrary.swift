import Foundation

/// Loads, downloads and caches the book.
///
/// **Content strategy:** the *Urtext* edition of "A Course in Miracles" is
/// freely available (Internet Archive, item `ACourseInMircalesUrtextEdition`).
/// The app downloads the plain OCR text (~4 MB) on first launch, caches it in
/// Application Support and keeps the parsed model as JSON next to it.
/// Nothing copyrighted is bundled inside the app binary.
@MainActor
final class BookLibrary: ObservableObject {

    enum State {
        case empty
        case downloading(progress: Double)
        case parsing
        case failed(String)
        case ready(ACIMBook)
    }

    @Published private(set) var state: State = .empty

    /// Sources for the Urtext plain text. Fallbacks are resolved in order.
    static let sources: [URL] = [
        URL(string: "https://archive.org/download/ACourseInMircalesUrtextEdition/ACourseInMiraclesUrtextEdition_djvu.txt")!,
    ]

    private var dataTask: Task<Void, Never>?

    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ACIM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var textFileURL: URL { supportDirectory.appendingPathComponent("urtext.txt") }
    private var modelFileURL: URL { supportDirectory.appendingPathComponent("book.json") }

    init() {
        Task { await restore() }
    }

    // MARK: - Restore

    func restore() async {
        if let book = Self.loadCachedModel(at: modelFileURL) {
            state = .ready(book)
            return
        }
        if let raw = try? String(contentsOf: textFileURL, encoding: .utf8) {
            state = .parsing
            let book = await parseInBackground(raw: raw)
            try? JSONEncoder().encode(book).write(to: modelFileURL, options: .atomic)
            state = .ready(book)
        } else {
            state = .empty
        }
    }

    // MARK: - Download

    func download() {
        dataTask?.cancel()
        dataTask = Task {
            var lastError: Error?
            for source in Self.sources {
                do {
                    try await downloadAndImport(from: source)
                    return
                } catch is CancellationError {
                    return
                } catch {
                    lastError = error
                    continue
                }
            }
            state = .failed(lastError.map { $0.localizedDescription } ?? "Download failed.")
        }
    }

    private func downloadAndImport(from url: URL) async throws {
        state = .downloading(progress: 0)
        let (data, _) = try await URLSession.shared.data(from: url)
        guard !data.isEmpty else {
            throw URLError(.zeroByteResource)
        }
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }
        try raw.write(to: textFileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: modelFileURL)
        state = .parsing
        let book = await parseInBackground(raw: raw)
        try JSONEncoder().encode(book).write(to: modelFileURL, options: .atomic)
        state = .ready(book)
    }

    /// Import a `.txt` file that the user picked in the Files app.
    func importTextFile(from url: URL, securityScoped: Bool) async {
        let needingAccess = securityScoped ? url.startAccessingSecurityScopedResource() : false
        defer { if needingAccess { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .isoLatin1) else {
            state = .failed("Could not read the selected file.")
            return
        }
        try? raw.write(to: textFileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: modelFileURL)
        state = .parsing
        let book = await parseInBackground(raw: raw)
        try? JSONEncoder().encode(book).write(to: modelFileURL, options: .atomic)
        state = .ready(book)
    }

    private nonisolated func parseInBackground(raw: String) async -> ACIMBook {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let book = ACIMParser.parse(raw)
                continuation.resume(returning: book)
            }
        }
    }

    // MARK: - Cache helpers

    static func loadCachedModel(at url: URL) -> ACIMBook? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ACIMBook.self, from: data)
    }

    var hasCachedModel: Bool {
        FileManager.default.fileExists(atPath: modelFileURL.path)
    }
}
