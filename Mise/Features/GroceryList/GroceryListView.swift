import SwiftUI

/// The hero screen. One list for the week, merged, aisle by aisle, in the order
/// the household walks the store. Section 5.3.
struct GroceryListView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: GroceryListStore?
    @State private var isAddingItem = false
    @State private var newItem = ""

    var body: some View {
        NavigationStack {
            Group {
                if let store, !store.isEmpty {
                    list(store)
                } else {
                    ContentUnavailableView {
                        Label("No grocery list yet", systemImage: "checklist")
                    } description: {
                        Text("Plan some meals, then tap Make the list. Mise merges what the recipes share, leaves out what is already in your pantry, and sorts the rest by aisle.")
                    } actions: {
                        Button("Make the list") { store?.regenerate() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("List")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newItem = ""
                        isAddingItem = true
                    } label: {
                        Label("Add an item", systemImage: "plus")
                    }
                }
            }
            .alert("Add an item", isPresented: $isAddingItem) {
                TextField("Dish soap, 2 lemons", text: $newItem)
                Button("Add") {
                    store?.addManual(newItem)
                    newItem = ""
                }
                Button("Cancel", role: .cancel) { newItem = "" }
            } message: {
                Text("Anything you add by hand stays on the list when you make it again.")
            }
        }
        .task {
            if store == nil {
                store = GroceryListStore(
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
    private func list(_ store: GroceryListStore) -> some View {
        List {
            if let problem = store.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(store.sections) { section in
                Section(section.aisle.displayName) {
                    ForEach(section.items, id: \.id) { item in
                        row(item, in: store)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { section.items[$0] }
                        for item in doomed { store.delete(item) }
                    }
                }
            }

            Section {
                Button {
                    store.regenerate()
                } label: {
                    Label("Make the list again", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text(footerText(store))
            }
        }
    }

    private func row(_ item: GroceryItem, in store: GroceryListStore) -> some View {
        Button {
            store.toggle(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? Color.accentColor : .secondary)
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    if let detail = amount(item) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if item.isManual {
                    Image(systemName: "hand.raised")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The note wins when it is set, because that is where a row with two
    /// quantities keeps its full written form.
    private func amount(_ item: GroceryItem) -> String? {
        if let note = item.note, !note.isEmpty { return note }
        guard let quantity = item.quantity, quantity > 0 else { return nil }
        return UnitConverter.format(Quantity(quantity, item.unit))
    }

    private func footerText(_ store: GroceryListStore) -> String {
        let remaining = store.remainingCount
        let made = store.generatedAt.map { date in
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Made \(formatter.localizedString(for: date, relativeTo: .now))."
        } ?? ""

        let left = remaining == 0
            ? "Everything is ticked off."
            : remaining == 1 ? "1 item left." : "\(remaining) items left."

        return [left, made].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

#Preview {
    GroceryListView()
        .environment(AppContainer(inMemory: true))
}
