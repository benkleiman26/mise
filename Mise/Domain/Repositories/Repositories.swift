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
    /// Deleting a recipe is supposed to take its ingredients and steps with
    /// it. On 2026-11-02 a reimport of 213 recipes proved it does not reliably
    /// do so: the recipes went and 2000 ingredient rows stayed, attached to
    /// nothing, invisible to every screen and counted by every query.
    ///
    /// So the children go explicitly, and anything already stranded can be
    /// swept up.
    /// Children arriving from the other phone have to be registered before
    /// they are attached. Same reason as `MealPlanRepository.insertEntry`: a
    /// model the store has no record of crashes partway through the save
    /// rather than being refused.
    func insertIngredient(_ ingredient: Ingredient)
    func insertStep(_ step: RecipeStep)
    func deleteIngredient(_ ingredient: Ingredient)
    func deleteStep(_ step: RecipeStep)
    /// Every ingredient and step there is, whatever recipe it belongs to, so a
    /// tombstone naming one can find it without knowing its parent.
    func allIngredients() throws -> [Ingredient]
    func allSteps() throws -> [RecipeStep]
    /// Only what has changed, asked of the store rather than filtered after.
    ///
    /// Sync asks this every thirty seconds, and walking 428 recipes and eight
    /// thousand ingredients and steps to discover that nothing changed is ten
    /// seconds of a phone that will not answer a touch. A fetch with a
    /// predicate normally returns nothing and costs nothing.
    /// Takes a recipe and its children out without recording a thing.
    ///
    /// For a caller that is about to put the same ids straight back. A
    /// re-import does exactly that, and recording it as a deletion tells the
    /// other phone to remove the recipe and tells the server to refuse the
    /// replacement, because a record a tombstone covers does not come back.
    /// That is how 26 recipes ended up existing on one phone, missing on the
    /// other, and rejected by the server in between.
    func replace(_ recipe: Recipe)
    func changed(since: Date) throws -> [Recipe]
    func changedIngredients(since: Date) throws -> [Ingredient]
    func changedSteps(since: Date) throws -> [RecipeStep]
    func orphanedIngredients() throws -> [Ingredient]
    /// Every ingredient that resolved to no grocery item, so the user can say
    /// what it is once. Section 5.3 rule 2.
    func uncategorisedIngredients() throws -> [Ingredient]
    func orphanedSteps() throws -> [RecipeStep]
    func save() throws
}

@MainActor
protocol CanonicalItemRepository {
    func all() throws -> [CanonicalItem]
    /// Same reason as `RecipeRepository.changed(since:)`.
    func changed(since: Date) throws -> [CanonicalItem]
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
    /// A meal built by a caller rather than by a fetch has to be registered
    /// before it is saved. Attaching it to a plan is not enough: the store
    /// crashes partway through the save rather than refusing it, which costs
    /// an afternoon to read.
    func insertEntry(_ meal: PlannedMeal)
    /// Removing a meal from `plan.entries` only breaks the link: the record
    /// would stay in the store with no plan. The caller needs a way to delete
    /// one, and it cannot reach the context itself.
    func deleteEntry(_ meal: PlannedMeal)
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
    /// Same reason as `MealPlanRepository.insertEntry`.
    func insertItem(_ item: GroceryItem)
    /// Same reason as `MealPlanRepository.deleteEntry`: regenerating a list
    /// replaces its rows, and a row dropped from the array would otherwise
    /// linger in the store forever.
    func deleteItem(_ item: GroceryItem)
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
