import SwiftUI

/// The library. 427 recipes, so this is mostly about narrowing them down.
struct RecipesView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: RecipesStore?
    @State private var plan: PlanStore?
    @State private var justAdded: String?
    @State private var isPickingTags = false
    @State private var isAddingByLink = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isAddingByLink = true
                    } label: {
                        Label("Add from a link", systemImage: "plus")
                    }
                }
                if let store {
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu(store)
                    }
                }
            }
            .sheet(isPresented: $isAddingByLink, onDismiss: { store?.load() }) {
                AddByLinkView()
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
        // A sync that arrives while this screen is open changes the database
        // underneath a view built from an earlier fetch. Without this the
        // list keeps showing what it showed and the sync looks broken.
        .onChange(of: container.dataVersion) {
            store?.load()
        }
    }

    // MARK: - The list

    @ViewBuilder
    private func library(_ store: RecipesStore) -> some View {
        let shown = store.visible

        List {
            Section {
                filterRow(store)
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
                        RecipeDetailView(recipe: recipe, onAdd: { add(recipe, servings: $0) })
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

    /// One row, and it does not scroll.
    ///
    /// It used to be two horizontally scrolling rows: one chip per dish type,
    /// which with a real library is twenty of them, and a second row holding
    /// everything else. On a phone that puts the fourth chip past the edge of
    /// the screen with nothing to say it is there, so the owner used the app
    /// for days without knowing the filters existed and found them only by
    /// scrolling to the far end, where Desserts and Snacks live.
    ///
    /// A menu holds all of its contents at once and says in its own label what
    /// is chosen, which is the thing a row of chips cannot do.
    @ViewBuilder
    private func filterRow(_ store: RecipesStore) -> some View {
        HStack(spacing: 8) {
            // Its own control rather than an item inside a list. This is the
            // one to reach for when it is 6pm and the alternative is ordering
            // in, and it can only do that job if it is in sight.
            chip("Standbys", systemImage: "bolt.fill", on: store.onlyStandbys) {
                store.onlyStandbys.toggle()
            }
            kindMenu(store)
            moreMenu(store)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private func kindMenu(_ store: RecipesStore) -> some View {
        let kinds = store.kinds
        let chosen = store.selectedKinds.count
        return Menu {
            if chosen > 0 {
                Button("Any kind") { store.selectedKinds = [] }
                Divider()
            }
            ForEach(kinds, id: \.kind) { entry in
                Button {
                    if store.selectedKinds.contains(entry.kind) {
                        store.selectedKinds.remove(entry.kind)
                    } else {
                        store.selectedKinds.insert(entry.kind)
                    }
                } label: {
                    Label(
                        "\(entry.kind.displayName)  \(entry.count)",
                        systemImage: store.selectedKinds.contains(entry.kind) ? "checkmark" : entry.kind.systemImage
                    )
                }
            }
        } label: {
            chipLabel(chosen == 0 ? "Kind" : "Kind \(chosen)", systemImage: "fork.knife", on: chosen > 0)
        }
        .disabled(kinds.isEmpty)
    }

    private func moreMenu(_ store: RecipesStore) -> some View {
        let on = store.onlyFavourites || store.onlyCooked || store.timeLimit != nil || !store.selectedTags.isEmpty
        return Menu {
            if store.hasFilters {
                Button(role: .destructive) { store.clearFilters() } label: {
                    Label("Clear the filters", systemImage: "xmark")
                }
                Divider()
            }
            Button {
                store.onlyFavourites.toggle()
            } label: {
                Label("Favourites", systemImage: store.onlyFavourites ? "checkmark" : "heart")
            }
            Button {
                store.onlyCooked.toggle()
            } label: {
                Label("Cooked before", systemImage: store.onlyCooked ? "checkmark" : "checkmark.circle")
            }
            Divider()
            ForEach(RecipesStore.TimeLimit.allCases) { limit in
                Button {
                    store.timeLimit = store.timeLimit == limit ? nil : limit
                } label: {
                    Label(limit.label, systemImage: store.timeLimit == limit ? "checkmark" : "clock")
                }
            }
            Divider()
            Button {
                isPickingTags = true
            } label: {
                Label(
                    store.selectedTags.isEmpty ? "Collections" : "Collections (\(store.selectedTags.count))",
                    systemImage: "folder"
                )
            }
        } label: {
            chipLabel("More", systemImage: "line.3.horizontal.decrease", on: on)
        }
    }

    /// The chip without a button around it, so a `Menu` can wear it as a label.
    private func chipLabel(_ title: String, systemImage: String, on: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(on ? Color.white : Color.primary)
    }


    private func chip(_ title: String, systemImage: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
    private func add(_ recipe: Recipe, servings: Int? = nil) {
        plan?.add(recipe, servings: servings)
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
