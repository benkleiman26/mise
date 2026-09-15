import SwiftUI

/// Section 7: four tabs, Plan, List, Recipes and Pantry, with Settings behind a
/// gear on Plan. Cook mode is presented full screen from a recipe and is Phase 3.
struct RootView: View {
    var body: some View {
        TabView {
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }

            GroceryListView()
                .tabItem { Label("List", systemImage: "checklist") }

            RecipesView()
                .tabItem { Label("Recipes", systemImage: "book") }

            PantryView()
                .tabItem { Label("Pantry", systemImage: "cabinet") }
        }
    }
}

#Preview {
    RootView()
        .environment(AppContainer(inMemory: true))
}
