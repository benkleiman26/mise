import SwiftUI

/// Section 5.7's paste a link, which is how Mealime took a recipe off a site
/// and the thing the owner used most.
///
/// It shows what it found before saving anything. An importer that silently
/// writes whatever it scraped is how a library fills up with navigation text.
struct AddByLinkView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var state: State = .idle
    @State private var store: AddByLinkStore?

    enum State: Equatable {
        case idle
        case loading
        case found(RecipeImporter.ImportedRecipe)
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading): true
            case (.found(let a), .found(let b)): a.title == b.title
            case (.failed(let a), .failed(let b)): a == b
            default: false
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Paste a link to a recipe", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit(look)
                    Button(action: look) {
                        if state == .loading {
                            Label("Reading the page", systemImage: "hourglass")
                        } else {
                            Label("Read the recipe", systemImage: "arrow.down.doc")
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || state == .loading)
                } footer: {
                    Text("Most recipe sites publish their recipes in a form Mise can read. A site behind a paywall or a sign in usually will not work.")
                }

                switch state {
                case .found(let recipe):
                    preview(recipe)
                case .failed(let message):
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                default:
                    EmptyView()
                }
            }
            .navigationTitle("Add from a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .found(let recipe) = state {
                        Button("Save") {
                            // The photo is fetched as part of saving, so the
                            // sheet waits rather than closing on a half done
                            // job.
                            state = .loading
                            Task {
                                await store?.save(recipe)
                                dismiss()
                            }
                        }
                        .disabled(state == .loading)
                    }
                }
            }
        }
        .task {
            if store == nil {
                store = AddByLinkStore(
                    recipes: container.recipes,
                    canonicalItems: container.canonicalItems,
                    households: container.households
                )
            }
        }
    }

    /// What it found, before anything is written. A bad read is obvious here
    /// and invisible once it is in the library.
    @ViewBuilder
    private func preview(_ recipe: RecipeImporter.ImportedRecipe) -> some View {
        Section("Found") {
            LabeledContent("Title", value: recipe.title)
            LabeledContent("Serves", value: "\(recipe.baseServings ?? 4)")
            if let minutes = recipe.cookMinutes, minutes > 0 {
                LabeledContent("Time", value: "\(minutes + (recipe.prepMinutes ?? 0)) min")
            }
        }

        Section("Ingredients, \(recipe.ingredientLines.count)") {
            ForEach(recipe.ingredientLines, id: \.self) { line in
                Text(line).font(.subheadline)
            }
        }

        if !recipe.steps.isEmpty {
            Section("Method, \(recipe.steps.count) steps") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { _, step in
                    Text(step).font(.subheadline).lineLimit(3)
                }
            }
        }
    }

    private func look() {
        let typed = address
        state = .loading
        Task {
            do {
                let recipe = try await RecipeWebImporter.load(typed)
                state = .found(recipe)
            } catch {
                state = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }
}
