import Foundation
import SwiftData
import XCTest
@testable import Mise

/// Seeding runs on every launch, so "it does nothing the second time" is the
/// property that matters most here.
@MainActor
final class SeedInstallerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var catalog: SeedCatalog!

    private var households: SwiftDataHouseholdRepository!
    private var users: SwiftDataUserRepository!
    private var canonicalItems: SwiftDataCanonicalItemRepository!
    private var recipes: SwiftDataRecipeRepository!
    private var pantry: SwiftDataPantryRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try MiseSchema.makeContainer(inMemory: true)
        context = ModelContext(container)
        catalog = try SeedCatalog.load()

        households = SwiftDataHouseholdRepository(context: context)
        users = SwiftDataUserRepository(context: context)
        canonicalItems = SwiftDataCanonicalItemRepository(context: context)
        recipes = SwiftDataRecipeRepository(context: context)
        pantry = SwiftDataPantryRepository(context: context)
    }

    override func tearDown() {
        households = nil
        users = nil
        canonicalItems = nil
        recipes = nil
        pantry = nil
        context = nil
        container = nil
        catalog = nil
        super.tearDown()
    }

    private func makeInstaller() -> SeedInstaller {
        SeedInstaller(
            households: households,
            users: users,
            canonicalItems: canonicalItems,
            recipes: recipes,
            pantry: pantry
        )
    }

    func testFirstRunSeedsOneHouseholdAndTheWholeLibrary() throws {
        let report = try makeInstaller().install(catalog)

        XCTAssertEqual(report.householdsInserted, 1)
        XCTAssertEqual(report.usersInserted, 1)
        XCTAssertEqual(report.canonicalItemsInserted, catalog.canonicalItems.count)
        XCTAssertEqual(report.recipesInserted, catalog.recipes.count)
        XCTAssertEqual(report.pantryEntriesInserted, catalog.canonicalItems.filter(\.isStaple).count)
        XCTAssertTrue(report.isClean, "Unresolved: \(report.unresolvedIngredients) \(report.unresolvedStepReferences)")

        XCTAssertEqual(try households.count(), 1)
        XCTAssertEqual(try canonicalItems.count(), 297)
        XCTAssertEqual(try recipes.count(), 12)
        XCTAssertEqual(try pantry.count(), 71)
    }

    /// The whole point of deriving ids from stable keys.
    func testSecondRunChangesNothing() throws {
        let first = try makeInstaller().install(catalog)
        XCTAssertTrue(first.insertedAnything)

        let counts = (
            households: try households.count(),
            users: try users.count(),
            items: try canonicalItems.count(),
            recipes: try recipes.count(),
            pantry: try pantry.count()
        )

        let second = try makeInstaller().install(catalog)

        XCTAssertFalse(second.insertedAnything)
        XCTAssertEqual(second, SeedReport())
        XCTAssertEqual(try households.count(), counts.households)
        XCTAssertEqual(try users.count(), counts.users)
        XCTAssertEqual(try canonicalItems.count(), counts.items)
        XCTAssertEqual(try recipes.count(), counts.recipes)
        XCTAssertEqual(try pantry.count(), counts.pantry)
    }

    /// A third run, to catch anything that is idempotent only once.
    func testAThirdRunAlsoChangesNothing() throws {
        let installer = makeInstaller()
        try installer.install(catalog)
        try installer.install(catalog)
        let third = try installer.install(catalog)
        XCTAssertFalse(third.insertedAnything)
        XCTAssertEqual(try recipes.count(), 12)
        XCTAssertEqual(try canonicalItems.count(), 297)
    }

    /// Section 5.1 again, this time on what actually reached the store rather
    /// than on what was in the file.
    func testEverySeededIngredientResolvedToACanonicalItem() throws {
        try makeInstaller().install(catalog)

        let knownIDs = try Set(canonicalItems.all().map(\.id))
        var checked = 0

        for recipe in try recipes.all() {
            XCTAssertFalse(recipe.ingredients.isEmpty, "\(recipe.title) has no ingredients")
            for ingredient in recipe.orderedIngredients {
                guard let canonicalItemID = ingredient.canonicalItemID else {
                    XCTFail("\(recipe.title): \"\(ingredient.name)\" did not resolve to a canonical item")
                    continue
                }
                XCTAssertTrue(
                    knownIDs.contains(canonicalItemID),
                    "\(recipe.title): \"\(ingredient.name)\" points at an item that is not in the table"
                )
                checked += 1
            }
        }

        XCTAssertEqual(checked, 97, "The seed library should have 97 ingredient lines in total")
    }

    /// Cook mode reads these, so a ref that points at nothing is a blank line on
    /// the step. Section 5.5.
    func testEveryStepReferencePointsAtAnIngredientOfTheSameRecipe() throws {
        try makeInstaller().install(catalog)

        var referencesChecked = 0
        for recipe in try recipes.all() {
            let own = Set(recipe.ingredients.map(\.id))
            for step in recipe.orderedSteps {
                for reference in step.ingredientRefs {
                    XCTAssertTrue(own.contains(reference), "\(recipe.title) step \(step.position + 1) points outside itself")
                    referencesChecked += 1
                }
            }
        }
        XCTAssertGreaterThan(referencesChecked, 0)
    }

    func testIngredientsAndStepsKeepTheirWrittenOrder() throws {
        try makeInstaller().install(catalog)

        let seed = try XCTUnwrap(catalog.recipes.first { $0.id == "seed-sheet-pan-salmon" })
        let recipe = try XCTUnwrap(recipes.find(id: StableID.recipe(seedID: seed.id)))

        XCTAssertEqual(recipe.orderedIngredients.map(\.name), seed.ingredients.map(\.name))
        XCTAssertEqual(recipe.orderedSteps.map(\.text), seed.steps.map(\.text))
        XCTAssertEqual(recipe.orderedIngredients.map(\.position), Array(0..<seed.ingredients.count))
    }

    /// Section 1a: this is what keeps salt and olive oil off every list.
    func testStaplesArePreSeededAsHave() throws {
        try makeInstaller().install(catalog)

        let itemsByID = try Dictionary(uniqueKeysWithValues: canonicalItems.all().map { ($0.id, $0) })
        let entries = try pantry.all()

        XCTAssertEqual(entries.count, 71)
        XCTAssertTrue(entries.allSatisfy { $0.status == .have })

        for entry in entries {
            let item = try XCTUnwrap(itemsByID[entry.canonicalItemID])
            XCTAssertTrue(item.isStaple, "\(item.name) is in the pantry but is not a staple")
        }

        let staples = try Set(canonicalItems.all().filter(\.isStaple).map(\.id))
        XCTAssertEqual(Set(entries.map(\.canonicalItemID)), staples)
    }

    /// Section 4 names the first household's settings exactly.
    func testTheFirstHouseholdHasThePreferencesTheSpecAsksFor() throws {
        try makeInstaller().install(catalog)

        let household = try XCTUnwrap(households.all().first)
        XCTAssertEqual(household.id, StableID.household())
        XCTAssertEqual(household.householdID, household.id)
        XCTAssertEqual(household.memberUserIDs.count, 1)

        let preferences = try XCTUnwrap(household.preferences)
        XCTAssertEqual(preferences.menuType, .pescetarian)
        XCTAssertEqual(preferences.restrictions, [])
        XCTAssertEqual(preferences.dislikedIngredients, ["olives"])
        XCTAssertEqual(preferences.defaultServings, 4)
        XCTAssertEqual(preferences.units, .us)
        XCTAssertEqual(preferences.aisleOrder, catalog.aisleOrder)
    }

    /// Phase 5 keys row level security on this, so nothing may be seeded without
    /// it. Section 2.
    func testEverySeededRecordBelongsToTheHousehold() throws {
        try makeInstaller().install(catalog)

        let householdID = StableID.household()
        XCTAssertTrue(try canonicalItems.all().allSatisfy { $0.householdID == householdID })
        XCTAssertTrue(try pantry.all().allSatisfy { $0.householdID == householdID })
        XCTAssertTrue(try users.all().allSatisfy { $0.householdID == householdID })

        for recipe in try recipes.all() {
            XCTAssertEqual(recipe.householdID, householdID)
            XCTAssertTrue(recipe.ingredients.allSatisfy { $0.householdID == householdID })
            XCTAssertTrue(recipe.steps.allSatisfy { $0.householdID == householdID })
        }
    }

    /// Two devices that seed before they ever sync must not produce two copies.
    func testASecondStoreSeedsTheSameIdentifiers() throws {
        try makeInstaller().install(catalog)
        let firstIDs = try Set(recipes.all().map(\.id))

        let otherContainer = try MiseSchema.makeContainer(inMemory: true)
        let otherContext = ModelContext(otherContainer)
        let other = SeedInstaller(
            households: SwiftDataHouseholdRepository(context: otherContext),
            users: SwiftDataUserRepository(context: otherContext),
            canonicalItems: SwiftDataCanonicalItemRepository(context: otherContext),
            recipes: SwiftDataRecipeRepository(context: otherContext),
            pantry: SwiftDataPantryRepository(context: otherContext)
        )
        try other.install(catalog)

        let secondIDs = try Set(SwiftDataRecipeRepository(context: otherContext).all().map(\.id))
        XCTAssertEqual(firstIDs, secondIDs)
    }
}
