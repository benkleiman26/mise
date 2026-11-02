import SwiftUI

/// One recipe, and the button the whole app is for. Cook mode, editing and the
/// nutrition panel are later phases; this is what you need to decide whether to
/// eat this on Tuesday.
struct RecipeDetailView: View {
    let recipe: Recipe
    /// Adds this recipe to the current week. Owned by the caller, which already
    /// holds the plan store.
    var onAdd: () -> Void

    @State private var hasAdded = false

    var body: some View {
        List {
            Section {
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Serves", value: "\(recipe.baseServings)")
                // An imported recipe usually has no times on it at all, and a
                // row reading "0 min" would be making one up.
                if recipe.prepMinutes > 0 {
                    LabeledContent("Prep", value: "\(recipe.prepMinutes) min")
                }
                if recipe.cookMinutes > 0 {
                    LabeledContent("Cook", value: "\(recipe.cookMinutes) min")
                }
                if recipe.totalMinutes == 0 {
                    LabeledContent("Time", value: "Not recorded")
                }
                if !recipe.tags.isEmpty {
                    LabeledContent("Tags", value: recipe.tags.joined(separator: ", "))
                }
            }

            Section("Ingredients") {
                ForEach(recipe.orderedIngredients, id: \.id) { ingredient in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line(for: ingredient))
                        if ingredient.isOptional {
                            Text("optional")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !recipe.steps.isEmpty {
                Section("Method") {
                    ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { index, step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Step \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(step.text)
                        }
                    }
                }
            }

            if let url = recipe.sourceURL {
                Section {
                    Link("Open the original", destination: url)
                }
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onAdd()
                // The button goes back to reading "Add to this week" on its
                // own, because adding the same dinner twice is a real thing
                // people do and a stuck "Added" label would say otherwise.
                hasAdded = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    hasAdded = false
                }
            } label: {
                let title: String = hasAdded ? "Added to this week" : "Add to this week"
                Label(title, systemImage: hasAdded ? "checkmark" : "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    /// "2 cups cooked white rice, rinsed". The quantity comes from the same
    /// formatter the grocery list uses, so the two screens never disagree.
    private func line(for ingredient: Ingredient) -> String {
        var parts: [String] = []
        if let quantity = ingredient.quantity {
            parts.append(UnitConverter.format(Quantity(quantity, ingredient.unit)))
        }
        parts.append(ingredient.name)

        var text = parts.joined(separator: " ")
        if let preparation = ingredient.preparation, !preparation.isEmpty {
            text += ", \(preparation)"
        }
        return text
    }
}
