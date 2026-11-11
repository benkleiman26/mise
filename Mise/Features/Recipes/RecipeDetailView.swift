import SwiftUI

/// One recipe, scaled to however many are eating, and the button the whole app
/// is for. Cook mode and full editing are later phases.
struct RecipeDetailView: View {
    let recipe: Recipe
    /// Adds this recipe to the current week at the serving count on screen.
    var onAdd: (Int) -> Void

    @Environment(AppContainer.self) private var container
    @State private var store: RecipeDetailStore?
    @State private var servings: Int?
    @State private var isCorrectingBase = false
    @State private var correctedBase = 4
    @State private var hasAdded = false

    /// What the screen is showing for, which starts at what the recipe says.
    private var shown: Int { servings ?? max(1, recipe.baseServings) }
    private var factor: Double {
        let base = max(1, recipe.baseServings)
        return Double(shown) / Double(base)
    }

    var body: some View {
        List {
            if let data = recipe.imageData, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                }
            } else if let address = recipe.imageURL {
                Section {
                    AsyncImage(url: address) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(height: 200)
                    .clipped()
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Stepper("Cooking for \(shown)", value: servingsBinding, in: 1...24)
                if recipe.prepMinutes > 0 {
                    LabeledContent("Prep", value: "\(recipe.prepMinutes) min")
                }
                if recipe.cookMinutes > 0 {
                    LabeledContent("Cook", value: "\(recipe.cookMinutes) min")
                }
                if recipe.totalMinutes == 0 {
                    LabeledContent("Time", value: "Not recorded")
                }
                if !recipe.kinds.isEmpty {
                    LabeledContent("Kind", value: recipe.kinds.map(\.displayName).joined(separator: ", "))
                }
                if !recipe.tags.isEmpty {
                    LabeledContent("Collections", value: recipe.tags.joined(separator: ", "))
                }
            }

            Section {
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
            } header: {
                Text("Ingredients")
            } footer: {
                writtenFor
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store?.toggleFavourite(recipe)
                } label: {
                    Label(
                        recipe.isFavorite ? "Remove from favorites" : "Add to favorites",
                        systemImage: recipe.isFavorite ? "heart.fill" : "heart"
                    )
                }
                .tint(.pink)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { addButton }
        .task {
            if store == nil {
                store = RecipeDetailStore(recipes: container.recipes)
            }
        }
        .alert("What does this recipe make?", isPresented: $isCorrectingBase) {
            TextField("Servings", value: $correctedBase, format: .number)
                .keyboardType(.numberPad)
            Button("Save") {
                store?.setBaseServings(correctedBase, on: recipe)
                servings = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The amounts below stay exactly as written. This only says how many people they feed, which is what everything else scales from.")
        }
    }

    private var servingsBinding: Binding<Int> {
        Binding(get: { shown }, set: { servings = $0 })
    }

    /// The honest footer. Scaling is only as good as the number it scales from,
    /// and that number was a guess on most of this library.
    @ViewBuilder
    private var writtenFor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if shown == recipe.baseServings {
                Text("As written, for \(recipe.baseServings).")
            } else {
                Text("Scaled from \(recipe.baseServings) to \(shown). The method still describes \(recipe.baseServings).")
            }
            Button("The amounts are not for \(recipe.baseServings)") {
                correctedBase = recipe.baseServings
                isCorrectingBase = true
            }
            .font(.footnote)
            if let problem = store?.problem {
                Text(problem).foregroundStyle(.secondary)
            }
        }
    }

    private var addButton: some View {
        Button {
            onAdd(shown)
            // It goes back to reading "Add to this week" on its own, because
            // adding the same dinner twice is a real thing people do and a
            // stuck "Added" label would say otherwise.
            hasAdded = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                hasAdded = false
            }
        } label: {
            let title: String = hasAdded ? "Added to this week" : "Add to this week, for \(shown)"
            Label(title, systemImage: hasAdded ? "checkmark" : "plus")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// "2 cups cooked white rice, rinsed", scaled to what is on screen. The
    /// quantity comes from the same formatter the grocery list uses, so the two
    /// screens never disagree about what three quarters of a pound looks like.
    private func line(for ingredient: Ingredient) -> String {
        var parts: [String] = []
        if let quantity = ingredient.quantity {
            parts.append(UnitConverter.format(Quantity(quantity * factor, ingredient.unit)))
        }
        parts.append(ingredient.name)

        var text = parts.joined(separator: " ")
        if let preparation = ingredient.preparation, !preparation.isEmpty {
            text += ", \(preparation)"
        }
        return text
    }
}
