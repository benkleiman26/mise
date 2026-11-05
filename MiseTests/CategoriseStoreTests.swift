import XCTest
import SwiftData
@testable import Mise

/// Section 5.3 rule 2. The owner's first import left 344 ingredient names that
/// matched nothing, and four rounds of editing the resource file by hand got it
/// to 52. The last ones are genuinely odd and only the cook knows what they
/// meant, so the app has to be able to learn them.
@MainActor
final class CategoriseStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var recipes: SwiftDataRecipeRepository!
    private var canonicalItems: SwiftDataCanonicalItemRepository!
    private var store: CategoriseStore!
    private let householdID = UUID()

    override func setUp() async throws {
        try await super.setUp()
        container = try MiseSchema.makeContainer(inMemory: true)
        context = ModelContext(container)
        recipes = SwiftDataRecipeRepository(context: context)
        canonicalItems = SwiftDataCanonicalItemRepository(context: context)
        store = CategoriseStore(recipes: recipes, canonicalItems: canonicalItems)
    }

    override func tearDown() async throws {
        store = nil
        recipes = nil
        canonicalItems = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    @discardableResult
    private func makeRecipe(title: String, ingredients: [String]) -> Recipe {
        let recipe = Recipe(householdID: householdID, title: title, sourceType: .imported, baseServings: 4)
        for (position, name) in ingredients.enumerated() {
            let ingredient = Ingredient(householdID: householdID, position: position, name: name)
            ingredient.recipe = recipe
            recipe.ingredients.append(ingredient)
        }
        recipes.insert(recipe)
        try? recipes.save()
        return recipe
    }

    @discardableResult
    private func makeItem(_ name: String, aisle: Aisle) -> CanonicalItem {
        let item = CanonicalItem(householdID: householdID, name: name, aisle: aisle)
        canonicalItems.insert(item)
        try? canonicalItems.save()
        return item
    }

    // MARK: - What is waiting

    func testTheMostUsedNameComesFirst() {
        makeRecipe(title: "A", ingredients: ["nduja", "lardo"])
        makeRecipe(title: "B", ingredients: ["nduja"])
        store.load()

        XCTAssertEqual(store.pending.map(\.name), ["nduja", "lardo"])
        XCTAssertEqual(store.pending.first?.count, 2)
        XCTAssertEqual(store.pending.first?.recipes, ["A", "B"], "so the cook can see what it was for")
    }

    func testAnIngredientThatAlreadyMatchesIsNotWaiting() {
        let item = makeItem("salt", aisle: .bakingAndSpices)
        let recipe = makeRecipe(title: "A", ingredients: ["salt"])
        recipe.orderedIngredients[0].canonicalItemID = item.id
        try? recipes.save()

        store.load()
        XCTAssertTrue(store.isEmpty)
    }

    // MARK: - Teaching

    func testTeachingAppliesToEveryRecipeAlreadyWaitingOnIt() throws {
        let chickpeas = makeItem("canned chickpeas", aisle: .cannedAndJarred)
        makeRecipe(title: "A", ingredients: ["garbanzo beans"])
        makeRecipe(title: "B", ingredients: ["Garbanzo Beans"])
        store.load()

        store.teach("garbanzo beans", as: chickpeas)

        XCTAssertTrue(store.isEmpty, "both rows were waiting on the same name")
        for ingredient in try recipes.uncategorisedIngredients() {
            XCTFail("\(ingredient.name) should have been categorised")
        }
        let all = try recipes.all().flatMap(\.ingredients)
        XCTAssertTrue(all.allSatisfy { $0.canonicalItemID == chickpeas.id })
        XCTAssertTrue(all.allSatisfy { $0.aisle == .cannedAndJarred }, "and moves to the right aisle")
    }

    func testTeachingIsRememberedOnTheItem() {
        let item = makeItem("canned chickpeas", aisle: .cannedAndJarred)
        makeRecipe(title: "A", ingredients: ["garbanzo beans"])
        store.load()

        store.teach("garbanzo beans", as: item)

        XCTAssertEqual(item.learnedAliases, ["garbanzo beans"])
        XCTAssertTrue(item.aliases.isEmpty, "it must not land in the shipped spellings, which seeding overwrites")
    }

    func testTeachingTheSameThingTwiceDoesNotRecordItTwice() {
        let item = makeItem("canned chickpeas", aisle: .cannedAndJarred)
        makeRecipe(title: "A", ingredients: ["garbanzo beans"])
        store.load()

        store.teach("garbanzo beans", as: item)
        store.teach("Garbanzo Beans", as: item)

        XCTAssertEqual(item.learnedAliases.count, 1)
    }

    func testWhatWasTaughtMatchesFromThenOn() {
        let item = makeItem("canned chickpeas", aisle: .cannedAndJarred)
        makeRecipe(title: "A", ingredients: ["garbanzo beans"])
        store.load()
        store.teach("garbanzo beans", as: item)

        // The next import builds a matcher from the store, and has to find it.
        let matcher = CanonicalMatcher(items: [CanonicalCandidate(item)])
        let match = matcher.match("garbanzo beans")

        XCTAssertEqual(match.item?.id, item.id)
        XCTAssertEqual(match.reason, .learned)
    }

    // MARK: - Choosing

    func testTheItemSearchMatchesWordByWord() {
        makeItem("canned chickpeas", aisle: .cannedAndJarred)
        makeItem("cherry tomatoes", aisle: .produce)
        store.load()

        store.query = "can chick"
        XCTAssertEqual(store.choices.map(\.name), ["canned chickpeas"])

        store.query = ""
        XCTAssertEqual(store.choices.count, 2)
    }
}
