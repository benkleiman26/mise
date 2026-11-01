import SwiftUI

/// Section 7: four tabs, Plan, List, Recipes and Pantry, with Settings behind a
/// gear on Plan. Cook mode is presented full screen from a recipe and is Phase 3.
///
/// The tab selection lives here because the loop the app exists for crosses
/// tabs: pick recipes, then make the list. "Make list" lands the user on the
/// list rather than leaving them to find it.
struct RootView: View {
    enum Tab: Hashable {
        case plan, list, recipes, pantry
    }

    @State private var tab: Tab = .plan

    var body: some View {
        TabView(selection: $tab) {
            PlanView(
                onBrowseRecipes: { tab = .recipes },
                onListMade: { tab = .list }
            )
            .tabItem { Label("Plan", systemImage: "calendar") }
            .tag(Tab.plan)

            GroceryListView()
                .tabItem { Label("List", systemImage: "checklist") }
                .tag(Tab.list)

            RecipesView()
                .tabItem { Label("Recipes", systemImage: "book") }
                .tag(Tab.recipes)

            PantryView()
                .tabItem { Label("Pantry", systemImage: "cabinet") }
                .tag(Tab.pantry)
        }
    }
}

#Preview {
    RootView()
        .environment(AppContainer(inMemory: true))
}
