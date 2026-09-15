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
        context.delete(entity)
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}

@MainActor
final class SwiftDataRecipeRepository: SwiftDataRepository<Recipe>, RecipeRepository {}

@MainActor
final class SwiftDataCanonicalItemRepository: SwiftDataRepository<CanonicalItem>, CanonicalItemRepository {}

@MainActor
final class SwiftDataPantryRepository: SwiftDataRepository<PantryEntry>, PantryRepository {}

@MainActor
final class SwiftDataMealPlanRepository: SwiftDataRepository<MealPlan>, MealPlanRepository {}

@MainActor
final class SwiftDataGroceryListRepository: SwiftDataRepository<GroceryList>, GroceryListRepository {}

@MainActor
final class SwiftDataHouseholdRepository: SwiftDataRepository<Household>, HouseholdRepository {}

@MainActor
final class SwiftDataUserRepository: SwiftDataRepository<User>, UserRepository {}
