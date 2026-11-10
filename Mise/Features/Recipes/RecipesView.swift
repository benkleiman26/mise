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

    /// Two controls on one line, and a line of words underneath when anything
    /// is on.
    ///
    /// This started as two horizontally scrolling rows of chips, one per dish
    /// type, which put the fourth chip off the edge of a phone with nothing to
    /// say it was there. Then it was four chips that did not fit, so every
    /// label was squeezed to one character a line. Then three chips whose
    /// labels disappeared entirely, because a `Label` short of room drops its
    /// title and keeps the icon, which leaves three unexplained symbols.
    ///
    /// The lesson of all three is the same: a row of controls does not survive
    /// a list of filters that grows. Twenty one dish types and forty
    /// collections were never going to fit on a line, and every attempt to
    /// make them fit cost the words that say what they are.
    ///
    /// So the controls live in a sheet, which has room to label everything and
    /// room to grow, and the line holds only the two things worth a tap
    /// without opening anything: the standbys, and a way in. What the sheet
    /// hides, the summary underneath says back in words.
    @ViewBuilder
    private func filterRow(_ store: RecipesStore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // The one shortcut that earns a place on the screen. It is
                // what gets tapped at 6pm when the alternative is ordering in,
                // and a shortcut inside a sheet is not a shortcut.
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
            if store.hasFilters {
                HStack(spacing: 8) {
                    Text(store.filterSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Clear") { store.clearFilters() }
                        .font(.footnote)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// Composed out of an image and a text rather than built from `Label`.
    ///
    /// A `Label` decides for itself how much of itself to show when space is
    /// tight, and what it gives up first is the words. On this row that turned
    /// three filters into three unlabelled symbols. Spelling it out means the
    /// title is not negotiable: it keeps its width and the row runs out of
    /// space honestly if it ever has to.
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

    @ViewBuilder
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

                Section("Time") {
                    ForEach(RecipesStore.TimeLimit.allCases) { limit in
                        toggleRow(limit.label, on: store.timeLimit == limit) {
                            store.timeLimit = store.timeLimit == limit ? nil : limit
                        }
                    }
                } footer: {
                    Text("A recipe with no time recorded is not known to be quick, so these leave it out rather than claim it.")
                }

                Section("Kind") {
                    ForEach(store.kinds, id: \.kind) { entry in
                        toggleRow(entry.kind.displayName, count: entry.count, on: store.selectedKinds.contains(entry.kind)) {
                            if store.selectedKinds.contains(entry.kind) {
                                store.selectedKinds.remove(entry.kind)
                            } else {
                                store.selectedKinds.insert(entry.kind)
                            }
                        }
                    }
                } footer: {
                    Text("Picking two means either one. A dish is rarely both.")
                }

                Section("Collections") {
                    ForEach(store.tags, id: \.name) { tag in
                        toggleRow(tag.name, count: tag.count, on: store.selectedTags.contains(tag.name)) {
                            if store.selectedTags.contains(tag.name) {
                                store.selectedTags.remove(tag.name)
                            } else {
                                store.selectedTags.insert(tag.name)
                            }
                        }
                    }
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
