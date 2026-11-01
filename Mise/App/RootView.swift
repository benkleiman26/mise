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

    @State private var screen: Screen = .plan

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
    }
}

#Preview {
    RootView()
        .environment(AppContainer(inMemory: true))
}
