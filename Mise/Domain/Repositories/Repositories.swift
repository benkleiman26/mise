import Foundation

/// Section 3: keep all persistence behind a Repository protocol so the backing
/// store can be swapped, and so the first build can run entirely on the local
/// store with sync stubbed. Phase 5 adds a Supabase backed implementation next
/// to the SwiftData one without any view changing.
///
/// One protocol per aggregate, written out with concrete types rather than
/// generics. The shared work lives in `SwiftDataRepository`, which is an
/// implementation detail these protocols say nothing about.
///
/// Nothing outside `Domain/Repositories` should touch a `ModelContext`.

@MainActor
protocol RecipeRepository {
    func all() throws -> [Recipe]
    func find(id: UUID) throws -> Recipe?
    func existingIDs() throws -> Set<UUID>
    func count() throws -> Int
    func insert(_ recipe: Recipe)
    func delete(_ recipe: Recipe)
    func save() throws
}

@MainActor
protocol CanonicalItemRepository {
    func all() throws -> [CanonicalItem]
    func find(id: UUID) throws -> CanonicalItem?
    func existingIDs() throws -> Set<UUID>
    func count() throws -> Int
    func insert(_ item: CanonicalItem)
    func delete(_ item: CanonicalItem)
    func save() throws
}

@MainActor
protocol PantryRepository {
    func all() throws -> [PantryEntry]
    func find(id: UUID) throws -> PantryEntry?
    func existingIDs() throws -> Set<UUID>
    func count() throws -> Int
    func insert(_ entry: PantryEntry)
    func delete(_ entry: PantryEntry)
    func save() throws
}

@MainActor
protocol MealPlanRepository {
    func all() throws -> [MealPlan]
    func find(id: UUID) throws -> MealPlan?
    func existingIDs() throws -> Set<UUID>
    func count() throws -> Int
    func insert(_ plan: MealPlan)
    func delete(_ plan: MealPlan)
    func save() throws
}

@MainActor
protocol GroceryListRepository {
    func all() throws -> [GroceryList]
    func find(id: UUID) throws -> GroceryList?
    func existingIDs() throws -> Set<UUID>
    func count() throws -> Int
    func insert(_ list: GroceryList)
    func delete(_ list: GroceryList)
    func save() throws
}

@MainActor
protocol HouseholdRepository {
    func all() throws -> [Household]
    func find(id: UUID) throws -> Household?
    func existingIDs() throws -> Set<UUID>
    func count() throws -> Int
    func insert(_ household: Household)
    func delete(_ household: Household)
    func save() throws
}

@MainActor
protocol UserRepository {
    func all() throws -> [User]
    func find(id: UUID) throws -> User?
    func existingIDs() throws -> Set<UUID>
    func count() throws -> Int
    func insert(_ user: User)
    func delete(_ user: User)
    func save() throws
}
