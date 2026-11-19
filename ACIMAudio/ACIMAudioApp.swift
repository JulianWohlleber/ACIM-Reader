import SwiftUI

@main
struct ACIMAudioApp: App {
    @StateObject private var library = BookLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
        }
    }
}
