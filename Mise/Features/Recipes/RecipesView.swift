import SwiftUI

/// The library. 427 recipes, so this is mostly about narrowing them down.
struct RecipesView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: RecipesStore?
    @State private var plan: PlanStore?
    @State private var justAdded: String?
    @State private var isFiltering = false
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
            }
        }
        // Pinned above the list rather than scrolling as a row inside it.
        //
        // As its own section it cost the gap between two sections plus the
        // second one's header, which came to most of a thumbnail of empty
        // screen between the controls and the first recipe. Here it costs what
        // it occupies, and it stays put while four hundred recipes scroll
        // past, which is what a control bar is for.
        .safeAreaInset(edge: .top, spacing: 0) {
            filterBar(store, showing: shown.count, of: store.items.count)
        }
        .searchable(
            text: Binding(get: { store.query }, set: { store.query = $0 }),
            prompt: "Search recipes or ingredients"
        )
        .sheet(isPresented: $isFiltering) {
            filterSheet(store)
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

    /// The control bar: two pills, and one line that says what you are looking
    /// at and why.
    ///
    /// This began as two horizontally scrolling rows of chips, one per dish
    /// type, which put the fourth off the edge of the phone with nothing to
    /// say it was there. Then four chips that did not fit, so every label was
    /// squeezed to one character a line. Then three that fit and lost their
    /// words, because a Label short of room gives up its title and keeps the
    /// icon.
    ///
    /// All three were the same mistake. Twenty one dish types and forty
    /// collections do not go on a line, and every way of making them fit
    /// spends the words that say what they are.
    ///
    /// So the line holds the two things worth a tap without opening anything,
    /// and the rest is a sheet. The count and the reason for it share a line,
    /// because they are one fact: "19 of 447" answers how many and says
    /// nothing about why, and the why was previously three controls away.
    @ViewBuilder
    private func filterBar(_ store: RecipesStore, showing: Int, of total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // The one shortcut that earns a place on the screen. It is what
                // gets tapped at 6pm when the alternative is ordering in, and a
                // shortcut inside a sheet is not a shortcut.
                pill("Standbys", systemImage: "bolt.fill", on: store.onlyStandbys) {
                    store.onlyStandbys.toggle()
                }
                pill(
                    store.filterCount == 0 ? "Filters" : "Filters \(store.filterCount)",
                    systemImage: "line.3.horizontal.decrease",
                    on: store.filterCount > 0
                ) {
                    isFiltering = true
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text(count(showing, of: total))
                    .foregroundStyle(.secondary)
                if store.hasFilters {
                    Text(store.filterSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Button("Clear") { store.clearFilters() }
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(.bar)
    }


    private func pill(_ title: String, systemImage: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
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

    /// Everything that narrows the list, in one sheet.
    ///
    /// Sections rather than a row, because a section has room for a heading
    /// that says what the choices are, and a row never did. The counts are
    /// here for the same reason they were on the chips: "Soups 12" tells you
    /// whether the tap is worth making, and twelve of four hundred is a
    /// different answer from two hundred.
    private func filterSheet(_ store: RecipesStore) -> some View {
        NavigationStack {
            List {
                Section {
                    toggleRow("Favourites", on: store.onlyFavourites) { store.onlyFavourites.toggle() }
                    toggleRow("Cooked before", on: store.onlyCooked) { store.onlyCooked.toggle() }
                }

                Section {
                    ForEach(RecipesStore.TimeLimit.allCases) { limit in
                        toggleRow(limit.label, on: store.timeLimit == limit) {
                            store.timeLimit = store.timeLimit == limit ? nil : limit
                        }
                    }
                } header: {
                    Text("Time")
                } footer: {
                    Text("A recipe with no time recorded is not known to be quick, so these leave it out rather than claim it.")
                }

                Section {
                    ForEach(store.kinds, id: \.kind) { entry in
                        toggleRow(entry.kind.displayName, count: entry.count, on: store.selectedKinds.contains(entry.kind)) {
                            if store.selectedKinds.contains(entry.kind) {
                                store.selectedKinds.remove(entry.kind)
                            } else {
                                store.selectedKinds.insert(entry.kind)
                            }
                        }
                    }
                } header: {
                    Text("Kind")
                } footer: {
                    Text("Picking two means either one. A dish is rarely both.")
                }

                Section {
                    ForEach(store.tags, id: \.name) { tag in
                        toggleRow(tag.name, count: tag.count, on: store.selectedTags.contains(tag.name)) {
                            if store.selectedTags.contains(tag.name) {
                                store.selectedTags.remove(tag.name)
                            } else {
                                store.selectedTags.insert(tag.name)
                            }
                        }
                    }
                } header: {
                    Text("Collections")
                } footer: {
                    Text("Picking two means both, which is how you narrow.")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear all") { store.clearFilters() }
                        .disabled(!store.hasFilters)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isFiltering = false }
                }
            }
        }
    }

    /// One row of the sheet. The whole row is the target, not the checkmark.
    private func toggleRow(_ title: String, count: Int? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let count {
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                }
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


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
