import SwiftUI

/// The library. Search, a detail screen, and the one action that matters:
/// putting a recipe on this week's plan.
struct RecipesView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: RecipesStore?
    @State private var plan: PlanStore?
    @State private var justAdded: String?

    var body: some View {
        NavigationStack {
            Group {
                if let store, !store.items.isEmpty {
                    library(store)
                } else {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book")
                    } description: {
                        Text("Write one down, paste a link, or bring over the recipes you already have. Mise reads the ingredients so the grocery list works straight away.")
                    }
                }
            }
            .navigationTitle("Recipes")
        }
        .task {
            if store == nil {
                store = RecipesStore(recipes: container.recipes)
            }
            if plan == nil {
                plan = PlanStore(
                    plans: container.mealPlans,
                    recipes: container.recipes,
                    households: container.households
                )
            }
            store?.load()
        }
    }

    @ViewBuilder
    private func library(_ store: RecipesStore) -> some View {
        let shown = store.visible

        List {
            if let problem = store.loadProblem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if shown.isEmpty {
                Text("Nothing matches \"\(store.query)\".")
                    .foregroundStyle(.secondary)
            }

            ForEach(shown, id: \.id) { recipe in
                NavigationLink {
                    RecipeDetailView(recipe: recipe, onAdd: { add(recipe) })
                } label: {
                    row(recipe)
                }
                .swipeActions(edge: .trailing) {
                    Button {
                        add(recipe)
                    } label: {
                        Label("Add to week", systemImage: "plus")
                    }
                    .tint(.accentColor)
                }
            }
        }
        .searchable(text: Binding(get: { store.query }, set: { store.query = $0 }), prompt: "Search recipes or ingredients")
        .overlay(alignment: .bottom) {
            if let justAdded {
                Text("\(justAdded) added to this week")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    // It sits over the list, so it must never take a touch.
                    .allowsHitTesting(false)
            }
        }
        .animation(.default, value: justAdded)
    }

    private func row(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.title)
                .font(.headline)
            if !recipe.summary.isEmpty {
                Text(recipe.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(recipe.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func add(_ recipe: Recipe) {
        plan?.add(recipe)
        justAdded = recipe.title

        let title = recipe.title
        Task {
            try? await Task.sleep(for: .seconds(2))
            if justAdded == title { justAdded = nil }
        }
    }
}

#Preview {
    RecipesView()
        .environment(AppContainer(inMemory: true))
}
