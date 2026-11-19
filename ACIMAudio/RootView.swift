import SwiftUI
import UniformTypeIdentifiers

/// Root switch: download / parse / read.
struct RootView: View {
    @EnvironmentObject private var library: BookLibrary

    var body: some View {
        switch library.state {
        case .ready(let book):
            ReaderScreen(book: book)
        case .downloading(let progress):
            DownloadView(progress: progress)
        case .parsing:
            DownloadView(progress: 1.0, parsing: true)
        case .failed(let message):
            FailureView(message: message)
        case .empty:
            WelcomeView()
        }
    }
}

// MARK: - Empty (first launch)

private struct WelcomeView: View {
    @EnvironmentObject private var library: BookLibrary
    @State private var importing = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "book.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("ACIM Reader")
                .font(.largeTitle.bold())
            Text("A Course in Miracles — Urtext Edition\nread aloud, sentence by sentence.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                library.download()
            } label: {
                Label("Download the book (about 4 MB)", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 320)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            Button("Import a .txt file instead") { importing = true }
                .font(.subheadline)
            Spacer()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
            if case .success(let url) = result {
                Task { await library.importTextFile(from: url, securityScoped: true) }
            }
        }
    }
}

// MARK: - Download progress

private struct DownloadView: View {
    let progress: Double
    var parsing = false

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: parsing ? nil : progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
            Text(parsing
                 ? "Preparing the book…"
                 : "Downloading the book… \(Int(progress * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Failure

private struct FailureView: View {
    @EnvironmentObject private var library: BookLibrary
    let message: String
    @State private var importing = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Download failed")
                .font(.title3.bold())
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { library.download() }
                .buttonStyle(.borderedProminent)
            Button("Import a .txt file instead") { importing = true }
                .font(.subheadline)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
            if case .success(let url) = result {
                Task { await library.importTextFile(from: url, securityScoped: true) }
            }
        }
    }
}
