import Foundation
import SwiftData

/// Every model in the app, in one place, so nothing can be added and quietly
/// left out of the container.
enum MiseSchema {
    static let models: [any PersistentModel.Type] = [
        Recipe.self,
        Ingredient.self,
        RecipeStep.self,
        CanonicalItem.self,
        PantryEntry.self,
        MealPlan.self,
        PlannedMeal.self,
        GroceryList.self,
        GroceryItem.self,
        Household.self,
        User.self,
        HouseholdPreferences.self,
    ]

    static var schema: Schema { Schema(models) }

    /// `inMemory` is what the tests use, and also what a preview would use.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
