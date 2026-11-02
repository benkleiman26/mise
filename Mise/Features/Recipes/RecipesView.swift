import SwiftUI

/// The library. 427 recipes, so this is mostly about narrowing them down.
struct RecipesView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: RecipesStore?
    @State private var plan: PlanStore?
    @State private var justAdded: String?
    @State private var isPickingTags = false

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
            .toolbar {
                if let store {
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu(store)
                    }
                }
            }
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

    // MARK: - The list

    @ViewBuilder
    private func library(_ store: RecipesStore) -> some View {
        let shown = store.visible

        List {
            Section {
                facets(store)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                if let problem = store.loadProblem {
                    Text(problem).font(.footnote).foregroundStyle(.secondary)
                }

                if shown.isEmpty {
                    emptyResult(store)
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
                    .swipeActions(edge: .leading) {
                        Button {
                            store.toggleFavourite(recipe)
                        } label: {
                            Label("Favourite", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                        }
                        .tint(.pink)
                    }
                }
            } header: {
                Text(count(shown.count, of: store.items.count))
            }
        }
        .searchable(
            text: Binding(get: { store.query }, set: { store.query = $0 }),
            prompt: "Search recipes or ingredients"
        )
        .sheet(isPresented: $isPickingTags) {
            tagPicker(store)
        }
        .overlay(alignment: .bottom) {
            if let justAdded {
                Text("\(justAdded) added to this week")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.default, value: justAdded)
    }

    private func row(_ recipe: Recipe) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RecipeThumbnail(recipe: recipe)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(recipe.title)
                        .font(.headline)
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                    }
                }
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
        }
        .padding(.vertical, 2)
    }

    // MARK: - Narrowing down

    @ViewBuilder
    private func facets(_ store: RecipesStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Favourites", systemImage: "heart", on: store.onlyFavourites) {
                    store.onlyFavourites.toggle()
                }
                chip("Cooked", systemImage: "checkmark", on: store.onlyCooked) {
                    store.onlyCooked.toggle()
                }
                ForEach(RecipesStore.TimeLimit.allCases) { limit in
                    chip(limit.label, systemImage: "clock", on: store.timeLimit == limit) {
                        store.timeLimit = store.timeLimit == limit ? nil : limit
                    }
                }
                chip(
                    store.selectedTags.isEmpty ? "Collections" : "\(store.selectedTags.count) collections",
                    systemImage: "folder",
                    on: !store.selectedTags.isEmpty
                ) {
                    isPickingTags = true
                }
                if store.hasFilters {
                    chip("Clear", systemImage: "xmark", on: false) {
                        store.clearFilters()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(_ title: String, systemImage: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func sortMenu(_ store: RecipesStore) -> some View {
        Menu {
            Picker("Sort", selection: Binding(get: { store.sort }, set: { store.sort = $0 })) {
                ForEach(RecipesStore.Sort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    @ViewBuilder
    private func tagPicker(_ store: RecipesStore) -> some View {
        NavigationStack {
            List {
                ForEach(store.tags, id: \.name) { tag in
                    Button {
                        if store.selectedTags.contains(tag.name) {
                            store.selectedTags.remove(tag.name)
                        } else {
                            store.selectedTags.insert(tag.name)
                        }
                    } label: {
                        HStack {
                            Text(tag.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(tag.count)").foregroundStyle(.secondary)
                            if store.selectedTags.contains(tag.name) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } 
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { store.selectedTags = [] }
                        .disabled(store.selectedTags.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPickingTags = false }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func emptyResult(_ store: RecipesStore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.query.isEmpty ? "Nothing matches those filters." : "Nothing matches \"\(store.query)\".")
            if store.hasFilters {
                Button("Clear the filters") { store.clearFilters() }
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private func count(_ shown: Int, of total: Int) -> String {
        if shown == total { return total == 1 ? "1 recipe" : "\(total) recipes" }
        return "\(shown) of \(total)"
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
