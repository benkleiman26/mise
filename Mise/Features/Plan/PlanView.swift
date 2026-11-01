import SwiftUI

/// The week's meals, and the button that turns them into a grocery list.
///
/// Section 5.2 keeps two ways of planning first class. This is the Mealime one,
/// a handful of dinners with no particular day. The calendar strip and
/// "Fill my week" are still to come.
struct PlanView: View {
    var onBrowseRecipes: () -> Void = {}
    var onListMade: () -> Void = {}

    @Environment(AppContainer.self) private var container
    @State private var store: PlanStore?
    @State private var groceries: GroceryListStore?
    @State private var isShowingSettings = false
    @State private var isConfirmingClear = false

    var body: some View {
        NavigationStack {
            Group {
                if let store, !store.entries.isEmpty {
                    week(store)
                } else {
                    ContentUnavailableView {
                        Label("No meals planned", systemImage: "calendar")
                    } description: {
                        Text("Pick a few dinners for the week and Mise turns them into one grocery list, grouped the way you walk the store.")
                    } actions: {
                        Button("Browse recipes", action: onBrowseRecipes)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("This week")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onBrowseRecipes()
                    } label: {
                        Label("Add a meal", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
        .task {
            if store == nil {
                store = PlanStore(
                    plans: container.mealPlans,
                    recipes: container.recipes,
                    households: container.households
                )
            }
            if groceries == nil {
                groceries = GroceryListStore(
                    lists: container.groceryLists,
                    plans: container.mealPlans,
                    recipes: container.recipes,
                    canonicalItems: container.canonicalItems,
                    pantry: container.pantry,
                    households: container.households
                )
            }
            store?.load()
        }
    }

    @ViewBuilder
    private func week(_ store: PlanStore) -> some View {
        List {
            if let problem = store.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(store.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.recipe.title)
                            .font(.headline)
                        Text("\(entry.recipe.totalMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Section 1a: servings per meal, not one number for the
                        // whole household.
                        Stepper(
                            "Serves \(entry.meal.servings)",
                            value: Binding(
                                get: { entry.meal.servings },
                                set: { store.setServings($0, for: entry) }
                            ),
                            in: 1...12
                        )
                        .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { offsets in
                    // Snapshot first: `remove` reloads the list, so reading
                    // `entries[index]` a second time would read a shifted row.
                    let doomed = offsets.map { store.entries[$0] }
                    for entry in doomed { store.remove(entry) }
                }
            } footer: {
                Text(mealCount(store.entries.count))
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Text("Clear the week")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                groceries?.regenerate()
                onListMade()
            } label: {
                Label("Make the list", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .confirmationDialog(
            "Clear this week's meals?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear the week", role: .destructive) { store.clear() }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("The grocery list stays as it is until you make it again.")
        }
    }

    private func mealCount(_ count: Int) -> String {
        count == 1 ? "1 meal" : "\(count) meals"
    }
}

#Preview {
    PlanView()
        .environment(AppContainer(inMemory: true))
}
