import SwiftUI

/// The library. Phase 0b lists what was seeded and nothing more: no search, no
/// filter chips, no collections, no detail screen. Those are Phase 1.
struct RecipesView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: RecipesStore?

    var body: some View {
        NavigationStack {
            Group {
                if let store, !store.items.isEmpty {
                    List(store.items, id: \.id) { recipe in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title)
                                .font(.headline)
                            Text(recipe.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(recipe.totalMinutes) min, serves \(recipe.baseServings)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
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
            store?.load()
        }
    }
}

#Preview {
    RecipesView()
        .environment(AppContainer(inMemory: true))
}
