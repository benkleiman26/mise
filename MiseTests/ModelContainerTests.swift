import Foundation
import SwiftData
import XCTest
@testable import Mise

/// Section 9's Phase 0b asks for a SwiftData container with all the models in
/// it. A model left out of `MiseSchema.models` fails at the first fetch rather
/// than at build time, so it is worth a test.
@MainActor
final class ModelContainerTests: XCTestCase {
    func testTheContainerBuildsWithEveryModelRegistered() throws {
        let container = try MiseSchema.makeContainer(inMemory: true)
        XCTAssertEqual(MiseSchema.models.count, 12)
        XCTAssertEqual(container.schema.entities.count, MiseSchema.models.count)
    }

    func testEveryModelCanBeFetched() throws {
        let container = try MiseSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Ingredient>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecipeStep>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CanonicalItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PantryEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealPlan>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedMeal>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<GroceryList>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<GroceryItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Household>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<User>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HouseholdPreferences>()), 0)
    }

    /// The repository is the only way anything is meant to reach the store, so
    /// the round trip is worth one check on its own.
    func testARepositoryRoundTrip() throws {
        let container = try MiseSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repository = SwiftDataRecipeRepository(context: context)

        let id = UUID()
        repository.insert(
            Recipe(
                id: id,
                householdID: StableID.household(),
                title: "Test",
                sourceType: .manual,
                baseServings: 2
            )
        )
        try repository.save()

        XCTAssertEqual(try repository.count(), 1)
        XCTAssertEqual(try repository.find(id: id)?.title, "Test")
        XCTAssertEqual(try repository.existingIDs(), [id])

        let stored = try XCTUnwrap(repository.find(id: id))
        repository.delete(stored)
        try repository.save()
        XCTAssertEqual(try repository.count(), 0)
    }

    /// Deleting a recipe should take its ingredients and steps with it.
    func testDeletingARecipeCascades() throws {
        let container = try MiseSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repository = SwiftDataRecipeRepository(context: context)
        let householdID = StableID.household()

        let recipe = Recipe(householdID: householdID, title: "Test", sourceType: .manual, baseServings: 2)
        recipe.ingredients = [Ingredient(householdID: householdID, position: 0, name: "salt")]
        recipe.steps = [RecipeStep(householdID: householdID, position: 0, text: "Season it.")]
        repository.insert(recipe)
        try repository.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Ingredient>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecipeStep>()), 1)

        repository.delete(recipe)
        try repository.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Ingredient>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecipeStep>()), 0)
    }
}
