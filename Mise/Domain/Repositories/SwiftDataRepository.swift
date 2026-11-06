import Foundation
import SwiftData

/// The shared SwiftData implementation. Every concrete repository is this class
/// with a type filled in, which keeps the protocols honest without writing the
/// same seven methods seven times.
///
/// Lookups by `id` filter in memory rather than through a predicate. That is a
/// deliberate Phase 0b choice: the largest table is 297 canonical items, the
/// seed path reads them once, and a `#Predicate` on a generic parameter is the
/// kind of thing that compiles and then fails at runtime against the schema.
/// See TODO.md, which says to revisit it when the library grows.
@MainActor
class SwiftDataRepository<Entity> where Entity: PersistentModel, Entity: HouseholdRecord {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() throws -> [Entity] {
        try context.fetch(FetchDescriptor<Entity>())
    }

    func find(id: UUID) throws -> Entity? {
        try all().first { $0.id == id }
    }

    func existingIDs() throws -> Set<UUID> {
        Set(try all().map(\.id))
    }

    func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<Entity>())
    }

    func insert(_ entity: Entity) {
        context.insert(entity)
    }

    func delete(_ entity: Entity) {
        recordDeletion(of: entity)
        context.delete(entity)
    }

    /// Leaves a tombstone, so the other phone learns the record is gone.
    ///
    /// Without one, sync has nothing to compare: the absence of a row is not
    /// information, and the next push from the other device would put the
    /// record straight back. A meal removed here would return, and a grocery
    /// item deleted in the shop would reappear.
    ///
    /// It is recorded even before anyone has signed in, because the deletes
    /// that happen before the first sync are exactly the ones that would
    /// otherwise come back when it starts.
    func recordDeletion<Record: HouseholdRecord>(of record: Record) {
        context.insert(
            Deletion(
                householdID: record.householdID,
                entity: Record.syncEntity,
                recordID: record.id,
                deviceID: DeviceIdentity.current
            )
        )
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}

@MainActor
final class SwiftDataRecipeRepository: SwiftDataRepository<Recipe>, RecipeRepository {
    func insertIngredient(_ ingredient: Ingredient) {
        context.insert(ingredient)
    }

    func insertStep(_ step: RecipeStep) {
        context.insert(step)
    }

    func allIngredients() throws -> [Ingredient] {
        try context.fetch(FetchDescriptor<Ingredient>())
    }

    func changed(since: Date) throws -> [Recipe] {
        try context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.updatedAt > since }))
    }

    func changedIngredients(since: Date) throws -> [Ingredient] {
        try context.fetch(FetchDescriptor<Ingredient>(predicate: #Predicate { $0.updatedAt > since }))
    }

    func changedSteps(since: Date) throws -> [RecipeStep] {
        try context.fetch(FetchDescriptor<RecipeStep>(predicate: #Predicate { $0.updatedAt > since }))
    }

    func allSteps() throws -> [RecipeStep] {
        try context.fetch(FetchDescriptor<RecipeStep>())
    }

    func deleteIngredient(_ ingredient: Ingredient) {
        recordDeletion(of: ingredient)
        context.delete(ingredient)
    }

    func deleteStep(_ step: RecipeStep) {
        recordDeletion(of: step)
        context.delete(step)
    }

    func uncategorisedIngredients() throws -> [Ingredient] {
        try context.fetch(FetchDescriptor<Ingredient>())
            .filter { $0.canonicalItemID == nil && $0.recipe != nil }
    }

    func orphanedIngredients() throws -> [Ingredient] {
        try context.fetch(FetchDescriptor<Ingredient>()).filter { $0.recipe == nil }
    }

    func orphanedSteps() throws -> [RecipeStep] {
        try context.fetch(FetchDescriptor<RecipeStep>()).filter { $0.recipe == nil }
    }
}

@MainActor
final class SwiftDataCanonicalItemRepository: SwiftDataRepository<CanonicalItem>, CanonicalItemRepository {
    func changed(since: Date) throws -> [CanonicalItem] {
        try context.fetch(FetchDescriptor<CanonicalItem>(predicate: #Predicate { $0.updatedAt > since }))
    }
}

@MainActor
final class SwiftDataPantryRepository: SwiftDataRepository<PantryEntry>, PantryRepository {}

@MainActor
final class SwiftDataMealPlanRepository: SwiftDataRepository<MealPlan>, MealPlanRepository {
    func insertEntry(_ meal: PlannedMeal) {
        context.insert(meal)
    }

    func deleteEntry(_ meal: PlannedMeal) {
        recordDeletion(of: meal)
        context.delete(meal)
    }
}

@MainActor
final class SwiftDataGroceryListRepository: SwiftDataRepository<GroceryList>, GroceryListRepository {
    func insertItem(_ item: GroceryItem) {
        context.insert(item)
    }

    func deleteItem(_ item: GroceryItem) {
        recordDeletion(of: item)
        context.delete(item)
    }
}

@MainActor
final class SwiftDataHouseholdRepository: SwiftDataRepository<Household>, HouseholdRepository {}

@MainActor
final class SwiftDataUserRepository: SwiftDataRepository<User>, UserRepository {}
