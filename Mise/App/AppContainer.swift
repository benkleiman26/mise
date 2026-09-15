import Foundation
import SwiftData

/// The one place that builds the store and hands out repositories.
///
/// Views reach for this through the SwiftUI environment and never see a
/// `ModelContext`. The model container is deliberately not published with
/// `.modelContainer(_:)`, because that is what would let a view start using
/// `@Query` and quietly route around section 3's rule that all persistence sits
/// behind a repository.
///
/// Every repository shares one `ModelContext`, so a `save()` on any of them
/// commits the work of all of them. That is what makes a seed run one
/// transaction rather than four.
@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer

    let households: any HouseholdRepository
    let users: any UserRepository
    let recipes: any RecipeRepository
    let canonicalItems: any CanonicalItemRepository
    let pantry: any PantryRepository
    let mealPlans: any MealPlanRepository
    let groceryLists: any GroceryListRepository

    /// What the last seed run did. Nil until it has run.
    private(set) var seedReport: SeedReport?

    /// Plain text for Settings when something went wrong on launch. Mise opens
    /// and says so rather than crashing, because section 0 asks for the first
    /// run to work for a stranger rather than only for the owner.
    private(set) var startupProblem: String?

    private var hasSeeded = false

    init(inMemory: Bool = false) {
        let store = Self.openStore(inMemory: inMemory)
        modelContainer = store.container

        let context = ModelContext(store.container)
        households = SwiftDataHouseholdRepository(context: context)
        users = SwiftDataUserRepository(context: context)
        recipes = SwiftDataRecipeRepository(context: context)
        canonicalItems = SwiftDataCanonicalItemRepository(context: context)
        pantry = SwiftDataPantryRepository(context: context)
        mealPlans = SwiftDataMealPlanRepository(context: context)
        groceryLists = SwiftDataGroceryListRepository(context: context)

        startupProblem = store.problem
    }

    /// Safe to call on every launch. `SeedInstaller` works out what is missing,
    /// which on the second launch is nothing.
    func seedIfNeeded() {
        guard !hasSeeded else { return }
        hasSeeded = true

        do {
            let catalog = try SeedCatalog.load()
            let installer = SeedInstaller(
                households: households,
                users: users,
                canonicalItems: canonicalItems,
                recipes: recipes,
                pantry: pantry
            )
            seedReport = try installer.install(catalog)
        } catch {
            startupProblem = "The starter recipes and grocery items could not be loaded. \(error)"
        }
    }

    /// Falls back to a memory only store rather than refusing to launch. A
    /// first run that cannot write is still worth showing; one that crashes is
    /// not.
    private static func openStore(inMemory: Bool) -> (container: ModelContainer, problem: String?) {
        do {
            return (try MiseSchema.makeContainer(inMemory: inMemory), nil)
        } catch {
            guard let fallback = try? MiseSchema.makeContainer(inMemory: true) else {
                fatalError("SwiftData could not build a container even in memory: \(error)")
            }
            return (fallback, "The local store could not be opened, so nothing you do will be saved. \(error)")
        }
    }
}
