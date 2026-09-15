import SwiftUI

@main
struct MiseApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .task { container.seedIfNeeded() }
        }
    }
}
