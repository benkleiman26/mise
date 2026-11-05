import SwiftUI

/// Section 7: four tabs, Plan, List, Recipes and Pantry, with Settings behind a
/// gear on Plan. Cook mode is presented full screen from a recipe and is Phase 3.
///
/// The tab selection lives here because the loop the app exists for crosses
/// tabs: pick recipes, then make the list. "Make the list" lands the user on the
/// list rather than leaving them to find it.
///
/// Built with the `Tab` values rather than `.tabItem` and `.tag`, which is the
/// spelling iOS 18 introduced and the SDK now expects. The enum is called
/// `Screen` because `Tab` is SwiftUI's own type.
///
/// This was first changed while chasing a reported scrolling bug that turned
/// out not to be a bug at all. It stays because it is the current API, not
/// because it fixed anything.
struct RootView: View {
    enum Screen: Hashable {
        case plan, list, recipes, pantry
    }

    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @State private var screen: Screen = .plan
    @State private var hasReadStartupProblem = false

    var body: some View {
        TabView(selection: $screen) {
            Tab("Plan", systemImage: "calendar", value: Screen.plan) {
                PlanView(
                    onBrowseRecipes: { screen = .recipes },
                    onListMade: { screen = .list }
                )
            }

            Tab("List", systemImage: "checklist", value: Screen.list) {
                GroceryListView()
            }

            Tab("Recipes", systemImage: "book", value: Screen.recipes) {
                RecipesView()
            }

            Tab("Pantry", systemImage: "cabinet", value: Screen.pantry) {
                PantryView()
            }
        }
        .task {
            // Sharing starts with the app, not with somebody opening Settings.
            container.startSyncing()
            await container.sync?.load()
            await container.sync?.syncIfPossible(force: true)

            // And keeps going while the app is open, so a tick in the shop
            // reaches the other phone without either person thinking about it.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await container.sync?.syncIfPossible()
            }
        }
        // Coming back to the app is the moment most likely to be out of date:
        // the other phone has had the whole time it was closed to change
        // something.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await container.sync?.syncIfPossible(force: true) }
        }
        // Said here rather than only in Settings.
        //
        // When the store will not open, the container falls back to memory so
        // the app still runs, and what the user sees is every recipe, the
        // week and the list gone. The explanation sat two taps away under
        // Settings, which is nowhere near where somebody looks when the app
        // comes up empty. An app that has lost its data has to say so on the
        // screen it opens on.
        .alert(
            "Mise could not open its data",
            isPresented: Binding(
                get: { container.startupProblem != nil && !hasReadStartupProblem },
                set: { if !$0 { hasReadStartupProblem = true } }
            )
        ) {
            Button("OK") { hasReadStartupProblem = true }
        } message: {
            Text("""
            Nothing you do now will be kept. Your recipes and your list are \
            still on the phone, they just are not loaded.

            \(container.startupProblem ?? "")
            """)
        }
    }
}

#Preview {
    RootView()
        .environment(AppContainer(inMemory: true))
}
