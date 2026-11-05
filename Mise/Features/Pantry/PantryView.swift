import SwiftUI

/// Section 5.4. What the household keeps on hand, and the one thing that keeps
/// salt and olive oil off every list.
///
/// Editable, because a status seeded once at install and never changed means
/// the list quietly leaves out eggs forever whether or not there are any.
struct PantryView: View {
    @Environment(AppContainer.self) private var container
    @State private var store: PantryStore?
    @State private var isAdding = false

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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAdding = true
                        } label: {
                            Label("Add an item", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                if let store {
                    AddPantryItemView(store: store)
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
        // A sync that arrives while this screen is open changes the database
        // underneath a view built from an earlier fetch. Without this the
        // list keeps showing what it showed and the sync looks broken.
        .onChange(of: container.dataVersion) {
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
                Button("Add an item") { isAdding = true }
                    .buttonStyle(.borderedProminent)
                Button("Show every grocery item") {
                    store.showsEverything = true
                    store.load()
                }
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


/// Adding to the pantry.
///
/// Two jobs in one sheet, because from the outside they are one job. Most of
/// the time the item is among the 395 Mise ships with and this only has to
/// find it, which the search already did but not in a way anybody would
/// discover. The rest of the time it is not, and the table has to learn it.
///
/// Offering the matches first is what keeps the grocery table honest: a second
/// row for "scallion" beside "green onion" would quietly stop the two merging
/// on the list, which is the one thing the table exists to do.
private struct AddPantryItemView: View {
    let store: PantryStore

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var aisle: Aisle = .other
    @State private var status: PantryStatus = .have

    private var cleaned: String { SeedCatalog.key(text) }
    private var matches: [PantryStore.Suggestion] { store.suggestions(for: text) }
    private var isNew: Bool { !cleaned.isEmpty && !store.isNameTaken(cleaned) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                } footer: {
                    Text("Lowercase and singular, the way the grocery table stores them: \"green onion\", not \"Green Onions\".")
                }

                Section("What you have") {
                    Picker("Status", selection: $status) {
                        Text("Have").tag(PantryStatus.have)
                        Text("Low").tag(PantryStatus.low)
                        Text("Out").tag(PantryStatus.out)
                    }
                    .pickerStyle(.segmented)
                }

                if !matches.isEmpty {
                    Section("Already in Mise") {
                        ForEach(matches) { match in
                            Button {
                                store.track(match, as: status)
                                dismiss()
                            } label: {
                                row(match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if isNew {
                    Section {
                        Picker("Aisle", selection: $aisle) {
                            ForEach(Aisle.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        Button("Add \"\(cleaned)\"") {
                            if store.addItem(named: cleaned, aisle: aisle, status: status) {
                                dismiss()
                            }
                        }
                    } header: {
                        Text("New item")
                    } footer: {
                        Text("Mise has never heard of this one. It joins the grocery table, so recipes that call for it will match it from now on.")
                    }
                }
            }
            .navigationTitle("Add to pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ match: PantryStore.Suggestion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.name)
                Text(match.matchedOn.map { "\(match.aisle.displayName), also called \($0)" } ?? match.aisle.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if match.isTracked {
                Text("Tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    PantryView()
        .environment(AppContainer(inMemory: true))
}
