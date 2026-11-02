import Foundation
import UIKit

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

    func save(_ imported: RecipeImporter.ImportedRecipe) async {
        // The photo first, because it is the only slow part and the rest of
        // the save should not be interleaved with a network wait.
        // A reference to `shrink` would not do: it has a defaulted second
        // parameter, so its type is not the one flatMap wants.
        let photo = await RecipeWebImporter.photo(at: imported.imageURLs?.first)
            .flatMap { Self.shrink($0) }

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
            let recipe = importer.build(imported, source: "link", into: &report)
            recipe.imageData = photo
            recipes.insert(recipe)
            try recipes.save()
            problem = nil
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "That could not be saved. \(error)"
        }
    }

    /// A recipe photo at a sensible size for a phone.
    ///
    /// Sites serve pictures sized for a desktop hero image, two thousand pixels
    /// and several megabytes. The library shows them at 56 points and the
    /// recipe screen at 200, so most of that is weight in the database and
    /// nothing on screen. Anything already small enough is left alone, because
    /// re-encoding a small image only loses quality.
    nonisolated static func shrink(_ data: Data, longestSide: CGFloat = 1200) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let side = max(image.size.width, image.size.height)
        guard side > longestSide else { return data }

        let scale = longestSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let smaller = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return smaller.jpegData(compressionQuality: 0.8) ?? data
    }
}
