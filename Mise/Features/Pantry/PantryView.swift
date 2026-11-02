import SwiftUI

/// Section 5.4. What the household keeps on hand, and the one thing that keeps
/// salt and olive oil off every list.
///
/// Editable, because a status seeded once at install and never changed means
/// the list quietly leaves out eggs forever whether or not there are any.
struct PantryView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: PantryStore?

    var body: some View {
        NavigationStack {
            Group {
                if let store, !store.isEmpty {
                    list(store)
                } else if let store {
                    empty(store)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Pantry")
            .toolbar {
                if let store {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.showsEverything.toggle()
                            store.load()
                        } label: {
                            Label(
                                store.showsEverything ? "Show what I track" : "Show everything",
                                systemImage: store.showsEverything ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                            )
                        }
                    }
                }
            }
        }
        .task {
            if store == nil {
                store = PantryStore(
                    pantry: container.pantry,
                    canonicalItems: container.canonicalItems,
                    households: container.households
                )
            }
            store?.load()
        }
    }

    @ViewBuilder
    private func list(_ store: PantryStore) -> some View {
        List {
            if let problem = store.loadProblem {
                Text(problem).font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(store.groups) { group in
                Section(group.aisle.displayName) {
                    ForEach(group.rows) { row in
                        PantryRow(row: row) { status in
                            store.set(status, for: row)
                        }
                    }
                }
            }
        }
        .searchable(
            text: Binding(
                get: { store.query },
                set: { store.query = $0; store.load() }
            ),
            prompt: "Search every grocery item"
        )
    }

    @ViewBuilder
    private func empty(_ store: PantryStore) -> some View {
        ContentUnavailableView {
            Label("Nothing in the pantry yet", systemImage: "cabinet")
        } description: {
            Text(store.query.isEmpty
                 ? "Track what you keep on hand and Mise leaves it off the grocery list, so salt and olive oil stop showing up every week."
                 : "Nothing matches \"\(store.query)\".")
        } actions: {
            if store.query.isEmpty {
                Button("Show every grocery item") {
                    store.showsEverything = true
                    store.load()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// One item, with the three answers the list generator cares about.
///
/// Section 4: `have` is left off the list, `low` and `out` are put on it. Not
/// tracked is a fourth state and deliberately different from `out`, because an
/// item nobody has said anything about should not be bought every week.
private struct PantryRow: View {
    let row: PantryStore.Row
    let onChange: (PantryStatus?) -> Void

    var body: some View {
        HStack {
            Text(row.name)
            Spacer()
            Picker("", selection: Binding(get: { row.status }, set: onChange)) {
                Text("Have").tag(PantryStatus?.some(.have))
                Text("Low").tag(PantryStatus?.some(.low))
                Text("Out").tag(PantryStatus?.some(.out))
                Text("Not tracked").tag(PantryStatus?.none)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(tint)
        }
    }

    private var tint: Color {
        switch row.status {
        case .have: .secondary
        case .low: .orange
        case .out: .red
        case nil: .secondary
        }
    }
}

#Preview {
    PantryView()
        .environment(AppContainer(inMemory: true))
}
