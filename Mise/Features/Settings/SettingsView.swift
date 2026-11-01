import SwiftUI
import UniformTypeIdentifiers

/// Behind the gear on Plan, per section 7. Mostly read only still: preference
/// editing and aisle reordering land with section 5.6. The recipe import from
/// section 5.7 lives here.
struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var store: SettingsStore?
    @State private var importer: ImportStore?
    @State private var isPickingFile = false

    var body: some View {
        NavigationStack {
            List {
                if let problem = container.startupProblem {
                    Section("Something went wrong") {
                        Text(problem)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Household") {
                    LabeledContent("Name", value: store?.household?.name ?? "Not set")
                    LabeledContent("Members", value: "Just you")
                }

                if let preferences = store?.household?.preferences {
                    Section {
                        LabeledContent("Menu type", value: preferences.menuType.rawValue.capitalized)
                        LabeledContent("Restrictions", value: list(preferences.restrictions.map(\.rawValue)))
                        LabeledContent("Dislikes", value: list(preferences.dislikedIngredients))
                        LabeledContent("Servings", value: "\(preferences.defaultServings)")
                        LabeledContent("Units", value: preferences.units == .us ? "US" : "Metric")
                        LabeledContent("Weeknight cap", value: "\(preferences.maxWeeknightMinutes) min")
                    } header: {
                        Text("Preferences")
                    } footer: {
                        Text("Changing these, rearranging your store aisles, and inviting someone else to the household are all still to come.")
                    }
                }

                Section {
                    LabeledContent("Recipes", value: "\(store?.recipeCount ?? 0)")
                    LabeledContent("Grocery items known", value: "\(store?.canonicalItemCount ?? 0)")
                    LabeledContent("Pantry entries", value: "\(store?.pantryCount ?? 0)")
                } header: {
                    Text("Library")
                } footer: {
                    seedFooter
                }

                importSection

                Section("About") {
                    LabeledContent("Version", value: store?.appVersion ?? "0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if store == nil {
                store = SettingsStore(
                    households: container.households,
                    recipes: container.recipes,
                    canonicalItems: container.canonicalItems,
                    pantry: container.pantry
                )
            }
            if importer == nil {
                importer = ImportStore(
                    recipes: container.recipes,
                    canonicalItems: container.canonicalItems,
                    households: container.households
                )
            }
            store?.load()
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importer?.importRecipes(from: url)
                store?.load()
            case .failure(let error):
                // The picker itself failed, which is not the same as the file
                // being wrong, so it is worth saying separately.
                print("The file could not be opened: \(error)")
            }
        }
    }

    /// Section 5.7. The file comes from `tools/mealime-import`, which runs on
    /// the owner's own machine, because the rescued library is personal and
    /// this repository is public.
    @ViewBuilder
    private var importSection: some View {
        Section {
            Button {
                isPickingFile = true
            } label: {
                if importer?.isWorking == true {
                    Label("Importing", systemImage: "hourglass")
                } else {
                    Label("Import recipes from a file", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(importer?.isWorking == true)

            if let report = importer?.report {
                LabeledContent("Added", value: "\(report.recipesInserted)")
                LabeledContent("Replaced", value: "\(report.recipesUpdated)")
                LabeledContent("Ingredient lines", value: "\(report.ingredientsRead)")
                if report.ingredientsNeedingReview > 0 {
                    LabeledContent("Lines worth a look", value: "\(report.ingredientsNeedingReview)")
                }
                if !report.unmatchedIngredients.isEmpty {
                    NavigationLink {
                        unmatchedList(report.unmatchedIngredients)
                    } label: {
                        LabeledContent("Not yet categorised", value: "\(report.unmatchedIngredients.count)")
                    }
                }
            }

            if let problem = importer?.problem {
                Text(problem)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Pick a Mise recipe import file. Importing the same file again replaces those recipes rather than adding a second copy of them.")
        }
    }

    private func unmatchedList(_ names: [String]) -> some View {
        List(names, id: \.self) { name in
            Text(name)
        }
        .navigationTitle("Not yet categorised")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var seedFooter: some View {
        if let report = container.seedReport, !report.isClean {
            Text("\(report.unresolvedIngredients.count) ingredients and \(report.unresolvedStepReferences.count) steps in the starter recipes did not match a known grocery item.")
        } else {
            Text("The starter recipes and the grocery item list are loaded on first launch and are not reloaded after that.")
        }
    }

    private func list(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }
}

#Preview {
    SettingsView()
        .environment(AppContainer(inMemory: true))
}
