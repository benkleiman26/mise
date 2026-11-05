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

    /// The same context the repositories share, for the one table that has no
    /// repository of its own: the deletion tombstones sync reads. Exposed
    /// rather than given a repository because nothing but sync will ever
    /// touch it, and a seventh protocol for one fetch would be ceremony.
    let syncContext: ModelContext

    /// What the last seed run did. Nil until it has run.
    private(set) var seedReport: SeedReport?

    /// Sharing, owned here rather than by the Settings screen.
    ///
    /// It used to be made by `SyncSettingsView` in its `.task`, which meant
    /// sync existed only while somebody was looking at Settings. Nothing can
    /// happen on its own under that arrangement.
    private(set) var sync: SyncStore?

    /// Bumped whenever a sync brings something in.
    ///
    /// Without it, syncing on its own is invisible: the database changes
    /// underneath a screen that was built from a fetch made before it, and
    /// the list keeps showing what it showed. Screens watch this and reload.
    private(set) var dataVersion = 0

    /// Plain text for Settings when something went wrong on launch. Mise opens
    /// and says so rather than crashing, because section 0 asks for the first
    /// run to work for a stranger rather than only for the owner.
    private(set) var startupProblem: String?

    private var hasSeeded = false

    /// Where seeding records what it has already offered.
    ///
    /// An in memory container is a test container, and a test must not read or
    /// write the device's own settings: one test would find the previous one's
    /// answers already recorded and quietly take a different path.
    private let defaults: UserDefaults

    init(inMemory: Bool = false) {
        defaults = inMemory ? Self.throwawayDefaults() : .standard
        let store = Self.openStore(inMemory: inMemory)
        modelContainer = store.container

        let context = ModelContext(store.container)
        syncContext = context
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
                pantry: pantry,
                defaults: defaults
            )
            seedReport = try installer.install(catalog)

            // After seeding, because a household has to exist before anything
            // can be keyed to it. Does nothing once there is nothing left to
            // merge, which is every launch after the first one that runs it.
            try DuplicateReconciler(
                households: households,
                mealPlans: mealPlans,
                groceryLists: groceryLists
            ).run()
        } catch {
            startupProblem = "The starter recipes and grocery items could not be loaded. \(error)"
        }
    }

    /// Made once, after the container exists, because it needs the container.
    func startSyncing() {
        guard sync == nil else { return }
        sync = SyncStore(container: self)
    }

    func dataChanged() {
        dataVersion += 1
    }

    /// Falls back to a memory only store rather than refusing to launch. A
    /// first run that cannot write is still worth showing; one that crashes is
    /// not.
    private static func throwawayDefaults() -> UserDefaults {
        let name = "mise.ephemeral.\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }

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
