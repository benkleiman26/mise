import SwiftUI

/// The hero screen. One list for the week, merged, aisle by aisle, in the order
/// the household walks the store. Section 5.3.
struct GroceryListView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: GroceryListStore?
    @State private var isAddingItem = false
    @State private var newItem = ""
    @State private var showing: GroceryItem?

    var body: some View {
        NavigationStack {
            Group {
                if let store, !store.isEmpty {
                    list(store)
                } else if let store, store.hasList, store.completedCount > 0 {
                    // Not the same as having no list, and saying so matters:
                    // offering "Make the list" to somebody who has just
                    // finished the shop would throw away what they did.
                    ContentUnavailableView {
                        Label("Everything is ticked off", systemImage: "checkmark.circle")
                    } description: {
                        Text(store.completedCount == 1
                             ? "One item, bought."
                             : "All \(store.completedCount) items, bought.")
                    } actions: {
                        Button("Show what I ticked off") { store.showsCompleted = true }
                            .buttonStyle(.borderedProminent)
                    }
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
                // Only once something has been ticked. Before that it is a
                // control for a state that does not exist.
                if let store, store.completedCount > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            store.showsCompleted.toggle()
                        } label: {
                            Label(
                                store.showsCompleted ? "Hide what I ticked off" : "Show what I ticked off",
                                systemImage: store.showsCompleted
                                    ? "line.3.horizontal.decrease.circle.fill"
                                    : "line.3.horizontal.decrease.circle"
                            )
                        }
                    }
                }
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
            .sheet(item: $showing) { item in
                if let store {
                    GroceryItemDetail(item: item, store: store) { showing = nil }
                }
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
                Text("\(footerText(store)) Press and hold an item to see which meals need it.")
            }
        }
    }

    /// A tap target, not a `Button`: `contentShape` plus `onTapGesture` gives
    /// the whole row the tap without a button's press styling, which on a
    /// checklist row reads as a glitch rather than as feedback.
    ///
    /// This was written to fix a scrolling report that turned out to be how
    /// the simulator was being driven. A `Button` here would have been fine.
    private func row(_ item: GroceryItem, in store: GroceryListStore) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            // Animated, because the row is about to leave the list and a row
            // that vanishes without moving reads as a glitch.
            withAnimation { store.toggle(item) }
        }
        // Ticking off is the thing a shopper does fifty times in a shop, so it
        // keeps the tap. Asking what a row is for is rarer and gets the longer
        // press.
        .onLongPressGesture(minimumDuration: 0.35) {
            showing = item
        }
    }

    private func amount(_ item: GroceryItem) -> String? {
        item.quantities.isEmpty ? nil : item.formatted
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

        let ticked = store.completedCount == 0 || store.showsCompleted
            ? ""
            : store.completedCount == 1 ? "1 ticked off, hidden." : "\(store.completedCount) ticked off, hidden."

        return [left, ticked, made].filter { !$0.isEmpty }.joined(separator: " ")
    }
}


/// One line on the list, and everything a person wants to do to it.
///
/// It was read only, which made it a dead end: the one place in the app that
/// shows what a line is and why it is there, with no way to fix a name the
/// parser got wrong, an amount that is not what the shop sells, or an aisle
/// that is wrong because nothing in the grocery table had heard of acai.
///
/// Edits are collected here and written once, on Done. Writing per keystroke
/// would stamp the record twelve times for one correction and hand the other
/// phone twelve changes to take.
private struct GroceryItemDetail: View {
    let item: GroceryItem
    let store: GroceryListStore
    let onDone: () -> Void

    @State private var name = ""
    @State private var amount = ""
    @State private var aisle: Aisle = .other
    @State private var hasRead = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Item", text: $name)
                    TextField("Amount", text: $amount)
                        .textInputAutocapitalization(.never)
                    Picker("Aisle", selection: $aisle) {
                        ForEach(Aisle.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } footer: {
                    // Says what the amount field actually accepts rather than
                    // what would be nice: it reads a number and a unit, so
                    // "a bunch" clears it instead of meaning anything.
                    Text(item.canonicalItemID == nil
                         ? "An amount needs a number: 2, 500 g, 1 bunch."
                         : "An amount needs a number: 2, 500 g, 1 bunch. Changing the aisle moves this item for good, on every list and on the other phone.")
                }

                Section("Needed for") {
                    let meals = store.meals(for: item)
                    if meals.isEmpty {
                        Text(item.isManual
                             ? "You added this one yourself."
                             : "Nothing in this week's plan, so this came from an earlier list.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(meals, id: \.self) { meal in
                            Text(meal)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.delete(item)
                        onDone()
                    } label: {
                        Text("Remove from the list")
                    }
                }
            }
            .navigationTitle(name.isEmpty ? item.displayName : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.update(item, name: name, amount: amount, aisle: aisle)
                        onDone()
                    }
                }
            }
            .onAppear {
                // Once. A reappear after the keyboard moves would otherwise
                // throw away what has been typed.
                guard !hasRead else { return }
                hasRead = true
                name = item.displayName
                amount = item.quantities.isEmpty ? "" : item.formatted
                aisle = item.aisle
            }
        }
        // Large as well, because half a screen with a keyboard over it leaves
        // room for about one field.
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    GroceryListView()
        .environment(AppContainer(inMemory: true))
}
