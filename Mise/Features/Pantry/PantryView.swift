import SwiftUI

/// What the household keeps on hand. Phase 0b shows the seeded staples read
/// only. Changing a status and adding an item are Phase 2, with the rest of
/// section 5.4.
struct PantryView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: PantryStore?

    var body: some View {
        NavigationStack {
            Group {
                if let store, !store.isEmpty {
                    List {
                        ForEach(store.groups) { group in
                            Section(group.aisle.displayName) {
                                ForEach(group.rows) { row in
                                    HStack {
                                        Text(row.name)
                                        Spacer()
                                        Text(label(for: row.status))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Nothing in the pantry yet", systemImage: "cabinet")
                    } description: {
                        Text("Track what you keep on hand and Mise leaves it off the grocery list, so salt and olive oil stop showing up every week.")
                    }
                }
            }
            .navigationTitle("Pantry")
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

    private func label(for status: PantryStatus) -> String {
        switch status {
        case .have: "Have"
        case .low: "Low"
        case .out: "Out"
        }
    }
}

#Preview {
    PantryView()
        .environment(AppContainer(inMemory: true))
}
