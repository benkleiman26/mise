import Foundation

/// The contents of `canonical_items.json` and `seed_recipes.json`, decoded and
/// cross checked, with nothing persisted yet.
///
/// This is deliberately free of SwiftData and SwiftUI. Everything about the seed
/// that can be got wrong (an unknown aisle, an ingredient that resolves to no
/// canonical item, a step pointing at an ingredient the recipe does not list) is
/// decided here, where it can be tested without a store or a screen.
/// `SeedInstaller` does the writing.
struct SeedCatalog: Sendable {
    let aisleOrder: [Aisle]
    let canonicalItems: [CanonicalItemSeed]
    let recipes: [RecipeSeed]

    /// Every name and alias, lowercased, pointing at the canonical item's name.
    /// Section 5.3 looks an ingredient up by exact name and then by alias, so
    /// the two share one namespace. `tools/resource-lint` refuses a collision.
    let lookup: [String: String]

    static func load(from bundle: Bundle = MiseBundle.resources) throws -> SeedCatalog {
        try SeedCatalog(
            canonicalItemsData: try data(named: "canonical_items", in: bundle),
            seedRecipesData: try data(named: "seed_recipes", in: bundle)
        )
    }

    init(canonicalItemsData: Data, seedRecipesData: Data) throws {
        let decoder = JSONDecoder()

        let items = try decoder.decode(CanonicalItemsDocument.self, from: canonicalItemsData)
        guard items.format == CanonicalItemsDocument.expectedFormat else {
            throw SeedError.unexpectedFormat(
                file: "canonical_items.json",
                found: items.format,
                expected: CanonicalItemsDocument.expectedFormat
            )
        }

        let seeds = try decoder.decode(SeedRecipesDocument.self, from: seedRecipesData)
        guard seeds.format == SeedRecipesDocument.expectedFormat else {
            throw SeedError.unexpectedFormat(
                file: "seed_recipes.json",
                found: seeds.format,
                expected: SeedRecipesDocument.expectedFormat
            )
        }

        self.aisleOrder = items.aisleOrder
        self.canonicalItems = items.items
        self.recipes = seeds.recipes

        var lookup: [String: String] = [:]
        for item in items.items {
            lookup[SeedCatalog.key(item.name)] = item.name
            for alias in item.aliases {
                lookup[SeedCatalog.key(alias)] = item.name
            }
        }
        self.lookup = lookup
    }

    /// The canonical item name a written ingredient resolves to, or nil.
    func canonicalName(for reference: String) -> String? {
        lookup[SeedCatalog.key(reference)]
    }

    /// Section 5.1 requires every seed ingredient to link to a canonical item,
    /// so anything this returns is a bug in the resource files rather than a
    /// case the app should handle at runtime.
    func unresolvedIngredients() -> [(recipe: String, reference: String)] {
        var problems: [(recipe: String, reference: String)] = []
        for recipe in recipes {
            for ingredient in recipe.ingredients where canonicalName(for: ingredient.canonicalKey) == nil {
                problems.append((recipe: recipe.id, reference: ingredient.canonicalKey))
            }
        }
        return problems
    }

    /// A step that names an ingredient the recipe does not list would show a
    /// blank line in cook mode. Section 5.5.
    func unresolvedStepReferences() -> [(recipe: String, step: Int, reference: String)] {
        var problems: [(recipe: String, step: Int, reference: String)] = []
        for recipe in recipes {
            let own = Set(recipe.ingredients.map { SeedCatalog.key($0.canonicalKey) })
            for (index, step) in recipe.steps.enumerated() {
                for reference in step.ingredientRefs where !own.contains(SeedCatalog.key(reference)) {
                    problems.append((recipe: recipe.id, step: index + 1, reference: reference))
                }
            }
        }
        return problems
    }

    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func data(named name: String, in bundle: Bundle) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw SeedError.missingResource("\(name).json")
        }
        return try Data(contentsOf: url)
    }
}

// MARK: - Decoded shapes

struct CanonicalItemSeed: Decodable, Sendable {
    let name: String
    let aisle: Aisle
    let aliases: [String]
    let defaultUnit: Unit?
    let isStaple: Bool

    private enum CodingKeys: String, CodingKey {
        case name, aisle, aliases, defaultUnit, isStaple
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        aisle = try container.decode(Aisle.self, forKey: .aisle)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        defaultUnit = try container.decodeIfPresent(Unit.self, forKey: .defaultUnit)
        isStaple = try container.decodeIfPresent(Bool.self, forKey: .isStaple) ?? false
    }
}

struct RecipeSeed: Decodable, Sendable {
    let id: String
    let title: String
    let summary: String
    let sourceType: RecipeSourceType
    let prepMinutes: Int
    let cookMinutes: Int
    let totalMinutes: Int
    let baseServings: Int
    let tags: [String]
    let cookware: [String]
    let ingredients: [IngredientSeed]
    let steps: [StepSeed]

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, sourceType, prepMinutes, cookMinutes, totalMinutes
        case baseServings, tags, cookware, ingredients, steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sourceType = try container.decodeIfPresent(RecipeSourceType.self, forKey: .sourceType) ?? .builtIn
        prepMinutes = try container.decodeIfPresent(Int.self, forKey: .prepMinutes) ?? 0
        cookMinutes = try container.decodeIfPresent(Int.self, forKey: .cookMinutes) ?? 0
        totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes) ?? 0
        baseServings = try container.decode(Int.self, forKey: .baseServings)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        cookware = try container.decodeIfPresent([String].self, forKey: .cookware) ?? []
        ingredients = try container.decode([IngredientSeed].self, forKey: .ingredients)
        steps = try container.decode([StepSeed].self, forKey: .steps)
    }
}

struct IngredientSeed: Decodable, Sendable {
    /// As written, which is what the cook reads.
    let name: String
    /// What the grocery list merges on. Absent means the written name is also
    /// the canonical one.
    let canonicalItem: String?
    let quantity: Double?
    let unit: Unit?
    let preparation: String?
    let isOptional: Bool

    private enum CodingKeys: String, CodingKey {
        case name, canonicalItem, quantity, unit, preparation, isOptional
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        canonicalItem = try container.decodeIfPresent(String.self, forKey: .canonicalItem)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decodeIfPresent(Unit.self, forKey: .unit)
        preparation = try container.decodeIfPresent(String.self, forKey: .preparation)
        isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
    }

    var canonicalKey: String { canonicalItem ?? name }
}

struct StepSeed: Decodable, Sendable {
    let text: String
    let timerSeconds: Int?
    /// Canonical item names, matching this recipe's own ingredients. The
    /// installer turns them into `Ingredient` ids.
    let ingredientRefs: [String]

    private enum CodingKeys: String, CodingKey {
        case text, timerSeconds, ingredientRefs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        timerSeconds = try container.decodeIfPresent(Int.self, forKey: .timerSeconds)
        ingredientRefs = try container.decodeIfPresent([String].self, forKey: .ingredientRefs) ?? []
    }
}

private struct CanonicalItemsDocument: Decodable {
    static let expectedFormat = "canonical-items"

    let format: String
    let version: Int
    let aisleOrder: [Aisle]
    let items: [CanonicalItemSeed]
}

private struct SeedRecipesDocument: Decodable {
    static let expectedFormat = "seed-recipes"

    let format: String
    let version: Int
    let recipes: [RecipeSeed]
}

// MARK: - Errors

enum SeedError: Error, CustomStringConvertible, Equatable {
    case missingResource(String)
    case unexpectedFormat(file: String, found: String, expected: String)
    case unresolvedIngredient(recipe: String, reference: String)

    var description: String {
        switch self {
        case .missingResource(let name):
            "\(name) is not in the app bundle."
        case .unexpectedFormat(let file, let found, let expected):
            "\(file) declares format \"\(found)\", expected \"\(expected)\"."
        case .unresolvedIngredient(let recipe, let reference):
            "Recipe \(recipe) refers to \"\(reference)\", which is not a canonical item."
        }
    }
}
