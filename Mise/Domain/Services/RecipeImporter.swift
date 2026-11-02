import Foundation

/// Reads a `mise-recipe-import` file and turns it into recipes.
///
/// Section 5.7. The Mealime rescue and the converter in `tools/mealime-import`
/// get the owner's library as far as a JSON file of recipes with their
/// ingredient lines written out as people write them. This is the other end:
/// it runs the same `IngredientParser` and `CanonicalMatcher` the rest of the
/// app uses, so an imported recipe behaves on the grocery list exactly like a
/// built in one.
///
/// Importing twice is safe. Every record's id is derived from the external id,
/// so a second run updates in place rather than producing a second library.
///
/// Free of SwiftData, SwiftUI and the file system: it takes `Data` and hands
/// back models. `ImportStore` does the reading and the writing.
struct RecipeImporter {
    static let expectedFormat = "mise-recipe-import"

    struct Document: Decodable {
        let format: String
        let version: Int
        let source: String?
        let recipes: [ImportedRecipe]
    }

    struct ImportedRecipe: Decodable {
        let externalID: String?
        let title: String
        let summary: String?
        let sourceURL: String?
        let prepMinutes: Int?
        let cookMinutes: Int?
        let baseServings: Int?
        let tags: [String]?
        let cookware: [String]?
        let ingredientLines: [String]
        let steps: [String]
        let imageURLs: [String]?
        let notes: String?
        let isFavorite: Bool?
        let timesCooked: Int?
    }

    /// What one run did, shown to the user rather than kept to ourselves.
    struct Report: Equatable, Sendable {
        var source: String = ""
        var recipesInserted = 0
        var recipesUpdated = 0
        var ingredientsRead = 0
        /// Lines the parser could not read a quantity from. They still import,
        /// as a name with no amount, which is what a shopper would write down.
        var ingredientsNeedingReview = 0
        /// Ingredient names that resolved to no canonical item. These land in
        /// aisle `other` on the list until the user categorises them.
        var unmatchedIngredients: [String] = []
        /// Ingredient and step rows left behind by an earlier import, cleared
        /// out. Anything above zero here means something leaked.
        var orphansSwept = 0

        var total: Int { recipesInserted + recipesUpdated }
    }

    enum ImportError: LocalizedError {
        case unexpectedFormat(found: String)
        case unreadable(String)
        case noHousehold

        var errorDescription: String? {
            switch self {
            case .unexpectedFormat(let found):
                return "That file is not a Mise recipe import. It says its format is \"\(found)\"."
            case .unreadable(let detail):
                return "That file could not be read. \(detail)"
            case .noHousehold:
                return "Mise has not finished setting up. Close the app and open it again."
            }
        }
    }

    let householdID: UUID
    let matcher: CanonicalMatcher

    static func decode(_ data: Data) throws -> Document {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw ImportError.unreadable("\(error)")
        }
        guard document.format == expectedFormat else {
            throw ImportError.unexpectedFormat(found: document.format)
        }
        return document
    }

    /// The id an imported recipe gets, so importing the same library twice
    /// updates rather than duplicates. A recipe with no external id falls back
    /// to its title, which is the best stable thing left.
    func id(for recipe: ImportedRecipe, source: String) -> UUID {
        let key = recipe.externalID ?? "title:\(recipe.title.lowercased())"
        return StableID.recipe(seedID: "import:\(source):\(key)")
    }

    /// Builds a recipe and everything hanging off it. The caller decides
    /// whether this is an insert or a replacement.
    func build(_ imported: ImportedRecipe, source: String, into report: inout Report) -> Recipe {
        let seedKey = "import:\(source):\(imported.externalID ?? "title:\(imported.title.lowercased())")"

        let recipe = Recipe(
            id: id(for: imported, source: source),
            householdID: householdID,
            title: imported.title,
            summary: imported.summary ?? "",
            sourceURL: imported.sourceURL.flatMap(URL.init(string:)),
            sourceType: .imported,
            prepMinutes: max(0, imported.prepMinutes ?? 0),
            cookMinutes: max(0, imported.cookMinutes ?? 0),
            baseServings: max(1, imported.baseServings ?? 4),
            tags: imported.tags ?? [],
            cookware: imported.cookware ?? [],
            imageURL: imported.imageURLs?.compactMap(URL.init(string:)).first,
            isFavorite: imported.isFavorite ?? false,
            timesCooked: max(0, imported.timesCooked ?? 0),
            notes: imported.notes ?? "",
            externalIDs: imported.externalID.map { [source: $0] } ?? [:]
        )

        for (position, line) in imported.ingredientLines.enumerated() {
            let parsed = IngredientParser.parse(line)
            let match = matcher.match(parsed.name)

            report.ingredientsRead += 1
            if parsed.confidence != .high { report.ingredientsNeedingReview += 1 }
            if match.item == nil, !parsed.name.isEmpty {
                report.unmatchedIngredients.append(parsed.name)
            }

            let ingredient = Ingredient(
                id: StableID.ingredient(recipeSeedID: seedKey, position: position),
                householdID: householdID,
                position: position,
                name: parsed.name.isEmpty ? line : parsed.name,
                canonicalItemID: match.item?.id,
                quantity: parsed.quantity,
                unit: parsed.unit,
                preparation: parsed.preparation,
                isOptional: parsed.isOptional,
                aisle: match.aisle
            )
            ingredient.recipe = recipe
            recipe.ingredients.append(ingredient)
        }

        for (position, text) in imported.steps.enumerated() {
            let step = RecipeStep(
                id: StableID.step(recipeSeedID: seedKey, position: position),
                householdID: householdID,
                position: position,
                text: text
            )
            step.recipe = recipe
            recipe.steps.append(step)
        }

        return recipe
    }
}
