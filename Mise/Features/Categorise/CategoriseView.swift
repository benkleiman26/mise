import SwiftUI

/// Section 5.3 rule 2, the screen. Every ingredient that resolved to nothing,
/// most used first, and a tap to say what it is.
struct CategoriseView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: CategoriseStore?
    @State private var choosing: CategoriseStore.Pending?

    var body: some View {
        Group {
            if let store, !store.isEmpty {
                waiting(store)
            } else {
                ContentUnavailableView {
                    Label("Everything is categorized", systemImage: "checkmark.circle")
                } description: {
                    Text("Every ingredient in your recipes matches a grocery item, so the list can merge them properly.")
                }
            }
        }
        .navigationTitle("Not yet categorized")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                store = CategoriseStore(
                    recipes: container.recipes,
                    canonicalItems: container.canonicalItems
                )
            }
            store?.load()
        }
        .sheet(item: $choosing) { pending in
            if let store {
                chooser(for: pending, in: store)
            }
        }
    }

    @ViewBuilder
    private func waiting(_ store: CategoriseStore) -> some View {
        List {
            if let problem = store.problem {
                Text(problem).font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                ForEach(store.pending) { pending in
                    Button {
                        // A fresh search each time, or the last one's filter is
                        // still applied to a different ingredient.
                        store.query = ""
                        choosing = pending
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pending.name)
                                .foregroundStyle(.primary)
                            Text(detail(pending))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } footer: {
                Text("These land in the Other aisle and will not merge with the same ingredient from another recipe. Tell Mise what one is and it remembers, including next time you import.")
            }
        }
        .overlay(alignment: .bottom) {
            if let taught = store.lastTaught {
                Text(taught)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
        .animation(.default, value: store.lastTaught)
    }

    private func detail(_ pending: CategoriseStore.Pending) -> String {
        let uses = pending.count == 1 ? "1 recipe" : "\(pending.count) recipes"
        guard let first = pending.recipes.first else { return uses }
        return pending.recipes.count > 1 ? "\(uses), including \(first)" : "\(uses): \(first)"
    }

    @ViewBuilder
    private func chooser(for pending: CategoriseStore.Pending, in store: CategoriseStore) -> some View {
        NavigationStack {
            List(store.choices, id: \.id) { item in
                Button {
                    store.teach(pending.name, as: item)
                    choosing = nil
                } label: {
                    LabeledContent {
                        Text(item.aisle.displayName)
                            .font(.caption)
                    } label: {
                        Text(item.name)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .searchable(
                text: Binding(get: { store.query }, set: { store.query = $0 }),
                prompt: "Search grocery items"
            )
            .navigationTitle(pending.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { choosing = nil }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
