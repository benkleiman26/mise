import SwiftUI

/// Behind the gear on Plan, per section 7. Read only for now: this phase is the
/// skeleton, and preference editing, aisle reordering and "Import from Mealime"
/// land with sections 5.6 and 5.7.
struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var store: SettingsStore?

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
            store?.load()
        }
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
