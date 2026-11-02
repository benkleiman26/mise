import Foundation

/// Saves a recipe read off a web page.
///
/// It goes through `RecipeImporter`, the same path the Mealime and NYT files
/// take, so a recipe pasted from a link is parsed, matched and categorised
/// exactly like every other recipe in the library. A second route into the
/// store would be a second set of answers.
@MainActor
@Observable
final class AddByLinkStore {
    private let recipes: any RecipeRepository
    private let canonicalItems: any CanonicalItemRepository
    private let households: any HouseholdRepository

    private(set) var problem: String?

    init(
        recipes: any RecipeRepository,
        canonicalItems: any CanonicalItemRepository,
        households: any HouseholdRepository
    ) {
        self.recipes = recipes
        self.canonicalItems = canonicalItems
        self.households = households
    }

    func save(_ imported: RecipeImporter.ImportedRecipe) {
        do {
            guard let household = try households.all().first else {
                throw RecipeImporter.ImportError.noHousehold
            }

            let importer = RecipeImporter(
                householdID: household.id,
                matcher: CanonicalMatcher(items: try canonicalItems.all().map(CanonicalCandidate.init)),
                alongside: nil
            )

            // Keyed on the url, so pasting the same link twice updates the
            // recipe rather than making a second copy of it.
            let id = importer.id(for: imported, source: "link")
            if let existing = try recipes.find(id: id) {
                for ingredient in existing.ingredients { recipes.deleteIngredient(ingredient) }
                for step in existing.steps { recipes.deleteStep(step) }
                recipes.delete(existing)
                try recipes.save()
            }

            var report = RecipeImporter.Report()
            recipes.insert(importer.build(imported, source: "link", into: &report))
            try recipes.save()
            problem = nil
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "That could not be saved. \(error)"
        }
    }
}
