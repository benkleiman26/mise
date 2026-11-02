import Foundation
import SwiftData

/// A recipe, from the seed library, an import, the user's own typing, or the AI
/// suggestion sheet. Section 4 asks for thin models, so the only behavior here
/// is `totalMinutes` and the two ordered accessors.
@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    var title: String
    var summary: String
    var sourceURL: URL?
    var sourceType: RecipeSourceType

    var prepMinutes: Int
    var cookMinutes: Int
    var baseServings: Int

    /// Flat and lowercase, per section 5.1.
    var tags: [String]
    /// What kind of dish this is, as `DishType` raw values. Worked out from
    /// the recipe rather than imported, because the tags that came with the
    /// library are the owner's own folders and answer a different question.
    ///
    /// Stored rather than computed: filtering reruns on every keystroke and
    /// reclassifying 427 recipes each time would be felt.
    var dishTypes: [String] = []
    /// Shown as a tab when present, the way Mealime does it. Section 1a.
    var cookware: [String]

    var imageURL: URL?
    @Attribute(.externalStorage) var imageData: Data?

    var isFavorite: Bool
    var timesCooked: Int
    var lastCookedAt: Date?
    var notes: String

    var nutritionPerServing: Nutrition?

    /// Keys such as `mealimeRecipeID`, `nytCookingID` and `seedID`, so a
    /// migration or a re-import can find what it already added. Section 4.
    var externalIDs: [String: String]

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient]

    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]

    init(
        id: UUID = UUID(),
        householdID: UUID,
        title: String,
        summary: String = "",
        sourceURL: URL? = nil,
        sourceType: RecipeSourceType,
        prepMinutes: Int = 0,
        cookMinutes: Int = 0,
        baseServings: Int,
        tags: [String] = [],
        dishTypes: [String] = [],
        cookware: [String] = [],
        imageURL: URL? = nil,
        imageData: Data? = nil,
        isFavorite: Bool = false,
        timesCooked: Int = 0,
        lastCookedAt: Date? = nil,
        notes: String = "",
        nutritionPerServing: Nutrition? = nil,
        externalIDs: [String: String] = [:],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.baseServings = baseServings
        self.tags = tags
        self.dishTypes = dishTypes
        self.cookware = cookware
        self.imageURL = imageURL
        self.imageData = imageData
        self.isFavorite = isFavorite
        self.timesCooked = timesCooked
        self.lastCookedAt = lastCookedAt
        self.notes = notes
        self.nutritionPerServing = nutritionPerServing
        self.externalIDs = externalIDs
        self.ingredients = []
        self.steps = []
    }

    /// Section 4 lists this as computed, and the seed file agrees with it for
    /// every recipe, which `SeedCatalogTests` checks.
    var totalMinutes: Int { prepMinutes + cookMinutes }

    var kinds: [DishType] { dishTypes.compactMap(DishType.init(rawValue:)) }

    /// "24 min", or nil when nobody ever wrote the time down.
    ///
    /// 159 of the owner's 213 rescued Mealime recipes have no cooking time,
    /// because Mealime leaves it null on a recipe you typed in yourself.
    /// Printing "0 min" on three quarters of a library states a cooking time
    /// that was never recorded, so the screens leave it out instead.
    var timingText: String? {
        totalMinutes > 0 ? "\(totalMinutes) min" : nil
    }

    /// The line under a recipe's title: "24 min, serves 4", or just the
    /// servings when the time is unknown.
    var summaryLine: String {
        let servings = "serves \(baseServings)"
        guard let timing = timingText else { return servings }
        return "\(timing), \(servings)"
    }

    /// SwiftData does not promise an order for a to-many relationship, so every
    /// ordered child carries a `position` and callers read it through here.
    var orderedIngredients: [Ingredient] { ingredients.sorted { $0.position < $1.position } }

    var orderedSteps: [RecipeStep] { steps.sorted { $0.position < $1.position } }
}
