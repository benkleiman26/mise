import XCTest
import SwiftData
@testable import Mise

/// Section 5.1. With 427 recipes the library screen is mostly about narrowing
/// them down, so the narrowing is what gets tested.
@MainActor
final class RecipesStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataRecipeRepository!
    private var store: RecipesStore!
    private let householdID = UUID()

    override func setUp() async throws {
        try await super.setUp()
        container = try MiseSchema.makeContainer(inMemory: true)
        repository = SwiftDataRecipeRepository(context: ModelContext(container))
        store = RecipesStore(recipes: repository)
    }

    override func tearDown() async throws {
        store = nil
        repository = nil
        container = nil
        try await super.tearDown()
    }

    @discardableResult
    private func add(
        _ title: String,
        minutes: Int = 30,
        tags: [String] = [],
        favourite: Bool = false,
        cooked: Int = 0,
        ingredients: [String] = []
    ) -> Recipe {
        let recipe = Recipe(
            householdID: householdID,
            title: title,
            sourceType: .imported,
            cookMinutes: minutes,
            baseServings: 4,
            tags: tags,
            isFavorite: favourite,
            timesCooked: cooked
        )
        for (position, name) in ingredients.enumerated() {
            let ingredient = Ingredient(householdID: householdID, position: position, name: name)
            ingredient.recipe = recipe
            recipe.ingredients.append(ingredient)
        }
        repository.insert(recipe)
        try? repository.save()
        return recipe
    }

    // MARK: - Search

    func testEveryWordTypedHasToAppearSomewhere() {
        add("Lemon Garlic Butter Pasta")
        add("Baked Feta Pasta")
        store.load()

        store.query = "lemon past"
        XCTAssertEqual(store.visible.map(\.title), ["Lemon Garlic Butter Pasta"],
                       "the bug from 2026-11-01: no title contains that run of characters")

        store.query = "pasta lemon"
        XCTAssertEqual(store.visible.count, 1, "order does not matter")
    }

    func testSearchReachesTheIngredients() {
        add("Mystery Dinner", ingredients: ["skinless chicken thighs", "rice"])
        store.load()

        store.query = "chicken"
        XCTAssertEqual(store.visible.count, 1, "what can I make with chicken is a real question")
    }

    // MARK: - Facets

    func testTheTimeFilterLeavesOutRecipesWithNoTimeRecorded() {
        add("Quick", minutes: 15)
        add("Slow", minutes: 90)
        add("Unknown", minutes: 0)
        store.load()

        store.timeLimit = .twenty
        XCTAssertEqual(store.visible.map(\.title), ["Quick"],
                       "159 of the owner's recipes have no time; claiming them would make the filter a lie")
    }

    func testTwoCollectionsNarrowRatherThanWiden() {
        add("Both", tags: ["Weeknights", "Pasta"])
        add("One", tags: ["Weeknights"])
        add("Other", tags: ["Pasta"])
        store.load()

        store.selectedTags = ["Weeknights"]
        XCTAssertEqual(store.visible.count, 2)

        store.selectedTags = ["Weeknights", "Pasta"]
        XCTAssertEqual(store.visible.map(\.title), ["Both"], "a second tap means narrow")
    }

    func testFavouritesAndCookedStack() {
        add("Loved and made", favourite: true, cooked: 3)
        add("Loved only", favourite: true)
        add("Made only", cooked: 1)
        store.load()

        store.onlyFavourites = true
        store.onlyCooked = true
        XCTAssertEqual(store.visible.map(\.title), ["Loved and made"])
    }

    func testFiltersAndSearchApplyTogether() {
        add("Lemon Pasta", tags: ["Weeknights"])
        add("Lemon Cake", tags: ["Baking"])
        store.load()

        store.query = "lemon"
        store.selectedTags = ["Weeknights"]
        XCTAssertEqual(store.visible.map(\.title), ["Lemon Pasta"])
    }

    func testClearingPutsEverythingBack() {
        add("A", tags: ["x"], favourite: true)
        add("B")
        store.load()

        store.selectedTags = ["x"]
        store.onlyFavourites = true
        store.timeLimit = .twenty
        XCTAssertTrue(store.hasFilters)

        store.clearFilters()
        XCTAssertFalse(store.hasFilters)
        XCTAssertEqual(store.visible.count, 2)
    }

    // MARK: - Collections

    func testCollectionsAreCountedAndMostUsedFirst() {
        add("A", tags: ["Weeknights", "Pasta"])
        add("B", tags: ["Weeknights"])
        add("C", tags: ["Weeknights"])
        store.load()

        XCTAssertEqual(store.tags.first?.name, "Weeknights")
        XCTAssertEqual(store.tags.first?.count, 3)
        XCTAssertEqual(store.tags.count, 2)
    }

    func testATagRepeatedOnOneRecipeIsCountedOnce() {
        add("A", tags: ["Pasta", "Pasta"])
        store.load()

        XCTAssertEqual(store.tags.first?.count, 1)
    }

    // MARK: - Sorting

    func testQuickestPutsUnknownTimesLastRatherThanFirst() {
        add("Unknown", minutes: 0)
        add("Slow", minutes: 90)
        add("Quick", minutes: 10)
        store.load()

        store.sort = .quickest
        XCTAssertEqual(store.visible.map(\.title), ["Quick", "Slow", "Unknown"],
                       "zero minutes means not recorded, not instant")
    }

    func testMostCookedThenAlphabetical() {
        add("Beta", cooked: 5)
        add("Alpha", cooked: 5)
        add("Never")
        store.load()

        store.sort = .mostCooked
        XCTAssertEqual(store.visible.map(\.title), ["Alpha", "Beta", "Never"])
    }

    // MARK: - Favouriting

    func testFavouritingSticks() throws {
        let recipe = add("A")
        store.load()

        store.toggleFavourite(recipe)
        XCTAssertTrue(try XCTUnwrap(repository.find(id: recipe.id)).isFavorite)

        store.toggleFavourite(recipe)
        XCTAssertFalse(try XCTUnwrap(repository.find(id: recipe.id)).isFavorite)
    }
}
