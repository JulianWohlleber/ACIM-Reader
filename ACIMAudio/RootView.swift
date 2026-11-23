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
    @Environment(\.colorScheme) private var scheme
    private var theme: RamsTheme { RamsTheme.current(scheme) }
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("ACIM Reader")
                .font(.ramsBold(32))
                .foregroundStyle(theme.inkC)
                .padding(.bottom, Grid.x(2))
            Text("A Course in Miracles — Urtext Edition\nread aloud, sentence by sentence.")
                .font(.rams(16))
                .foregroundStyle(theme.inkMutedC)
                .multilineTextAlignment(.leading)
                .padding(.bottom, Grid.x(4))
            Rectangle().fill(theme.hairlineC).frame(height: 0.5)
                .padding(.bottom, Grid.x(4))

            Button {
                library.download()
            } label: {
                Text("Download the book (about 4 MB)")
                    .font(.ramsMedium(15))
                    .foregroundStyle(theme.paperC)
                    .frame(maxWidth: .infinity)
                    .frame(height: Grid.x(7))
                    .background(theme.inkC)
            }
            .buttonStyle(.plain)

            Button { importing = true } label: {
                Text("Import a .txt file instead")
                    .panelLabel(theme)
                    .frame(maxWidth: .infinity)
                    .frame(height: Grid.x(7))
            }
            .buttonStyle(.plain)
            .padding(.top, Grid.x(1))
            Spacer()
        }
        .padding(.horizontal, Grid.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paperC.ignoresSafeArea())
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
    @Environment(\.colorScheme) private var scheme
    private var theme: RamsTheme { RamsTheme.current(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: Grid.x(2)) {
            Text(parsing
                 ? "Preparing the book…"
                 : "Downloading the book… \(Int(progress * 100))%")
                .font(.ramsMedium(15))
                .foregroundStyle(theme.inkC)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(theme.hairlineC)
                    Rectangle().fill(theme.accentC)
                        .frame(width: geo.size.width * CGFloat(min(max(parsing ? 1 : progress, 0), 1)))
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, Grid.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paperC.ignoresSafeArea())
    }
}

// MARK: - Failure

private struct FailureView: View {
    @EnvironmentObject private var library: BookLibrary
    @Environment(\.colorScheme) private var scheme
    private var theme: RamsTheme { RamsTheme.current(scheme) }
    let message: String
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("Download failed")
                .font(.ramsBold(24))
                .foregroundStyle(theme.inkC)
                .padding(.bottom, Grid.x(2))
            Text(message)
                .font(.rams(16))
                .foregroundStyle(theme.inkMutedC)
                .multilineTextAlignment(.leading)
                .padding(.bottom, Grid.x(4))
            Rectangle().fill(theme.hairlineC).frame(height: 0.5)
                .padding(.bottom, Grid.x(4))

            Button { library.download() } label: {
                Text("Retry")
                    .font(.ramsMedium(15))
                    .foregroundStyle(theme.paperC)
                    .frame(maxWidth: .infinity)
                    .frame(height: Grid.x(7))
                    .background(theme.inkC)
            }
            .buttonStyle(.plain)

            Button { importing = true } label: {
                Text("Import a .txt file instead")
                    .panelLabel(theme)
                    .frame(maxWidth: .infinity)
                    .frame(height: Grid.x(7))
            }
            .buttonStyle(.plain)
            .padding(.top, Grid.x(1))
            Spacer()
        }
        .padding(.horizontal, Grid.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.paperC.ignoresSafeArea())
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
            if case .success(let url) = result {
                Task { await library.importTextFile(from: url, securityScoped: true) }
            }
        }
    }
}
