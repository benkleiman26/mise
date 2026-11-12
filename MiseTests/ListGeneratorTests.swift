import XCTest
@testable import Mise

/// ListGenerator, driven from `Fixtures/list_generation.json` over the real
/// seed library.
///
/// The scenarios name actual recipe ids, so `tools/resource-lint` recomputes
/// each expected list from the real recipe data, the real canonical table and
/// the unit arithmetic. Nothing here was taken on trust before it compiled.
///
/// Section 2 calls the grocery list the hero and says anything that cannot be
/// turned into a clean, aisle grouped, deduplicated list is a bug. This is
/// where that claim is tested.
final class ListGeneratorTests: XCTestCase {

    // MARK: - Loading

    private struct CanonicalFile: Decodable {
        struct Item: Decodable {
            let name: String
            let aliases: [String]?
            let aisle: Aisle
            let isStaple: Bool?
            let defaultUnit: Mise.Unit?
        }
        let items: [Item]
        let aisleOrder: [Aisle]
    }

    private struct SeedFile: Decodable {
        struct Recipe: Decodable {
            let id: String
            let title: String
            let baseServings: Int
            let ingredients: [Ingredient]
        }
        struct Ingredient: Decodable {
            let name: String
            let canonicalItem: String?
            let quantity: Double?
            let unit: Mise.Unit?
            let isOptional: Bool?
        }
        let recipes: [Recipe]
    }

    private struct Fixtures: Decodable {
        struct Scenario: Decodable {
            struct Meal: Decodable {
                let recipe: String
                let servings: Int
            }
            struct Expected: Decodable {
                let item: String
                let aisle: Aisle
                let formatted: String?
                let sources: Int?
            }
            let name: String
            let why: String?
            let plan: [Meal]
            /// Either the string "allStaples" or a list of canonical names.
            let pantryHave: PantryHave
            let expect: [Expected]
            let expectAbsent: [String]?
        }

        enum PantryHave: Decodable {
            case allStaples
            case named([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self), text == "allStaples" {
                    self = .allStaples
                } else {
                    self = .named(try container.decode([String].self))
                }
            }
        }

        let scenarios: [Scenario]
    }

    private static func load<T: Decodable>(_ type: T.Type, _ resource: String, from bundle: Bundle) -> T {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            fatalError("\(resource).json is not in the bundle. Check the target's resources.")
        }
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private static let canonical = load(CanonicalFile.self, "canonical_items", from: MiseBundle.resources)
    private static let seed = load(SeedFile.self, "seed_recipes", from: MiseBundle.resources)
    private static let fixtures = load(Fixtures.self, "list_generation", from: Bundle(for: ListGeneratorTests.self))

    private static let candidates: [CanonicalCandidate] = canonical.items.map {
        CanonicalCandidate(
            id: StableID.canonicalItem(name: $0.name),
            name: $0.name,
            aliases: $0.aliases ?? [],
            aisle: $0.aisle,
            isStaple: $0.isStaple ?? false,
            defaultUnit: $0.defaultUnit
        )
    }

    private static let matcher = CanonicalMatcher(items: candidates)
    private static let staples = Set(
        canonical.items.filter { $0.isStaple == true }.map { StableID.canonicalItem(name: $0.name) }
    )

    private static func recipeInput(_ id: String) -> RecipeInput {
        guard let recipe = seed.recipes.first(where: { $0.id == id }) else {
            fatalError("the fixture names a recipe that is not in the seed library: \(id)")
        }
        return RecipeInput(
            id: StableID.recipe(seedID: recipe.id),
            title: recipe.title,
            baseServings: recipe.baseServings,
            ingredients: recipe.ingredients.map {
                IngredientInput(
                    name: $0.name,
                    quantity: $0.quantity,
                    unit: $0.unit,
                    isOptional: $0.isOptional ?? false,
                    canonicalItemID: $0.canonicalItem.map(StableID.canonicalItem(name:))
                )
            }
        )
    }

    private func generator(for scenario: Fixtures.Scenario) -> ListGenerator {
        let have: Set<UUID>
        switch scenario.pantryHave {
        case .allStaples:
            have = Self.staples
        case .named(let names):
            have = Set(names.map(StableID.canonicalItem(name:)))
        }
        return ListGenerator(matcher: Self.matcher, pantryHave: have, aisleOrder: Self.canonical.aisleOrder)
    }

    // MARK: - The scenarios

    func testScenarios() {
        for scenario in Self.fixtures.scenarios {
            let plan = scenario.plan.map { PlannedMealInput(recipe: Self.recipeInput($0.recipe), servings: $0.servings) }
            let list = generator(for: scenario).generate(plan: plan)
            let actual = list.items
            let label = scenario.why.map { "\(scenario.name)  (\($0))" } ?? scenario.name

            XCTAssertEqual(
                actual.count,
                scenario.expect.count,
                "\(label): wrong number of lines. Got: \(actual.map { "\($0.displayName) \($0.formatted)" })"
            )
            guard actual.count == scenario.expect.count else { continue }

            for (index, line) in actual.enumerated() {
                let want = scenario.expect[index]
                let at = "\(label), line \(index + 1)"
                XCTAssertEqual(line.displayName, want.item, "\(at): item")
                XCTAssertEqual(line.aisle, want.aisle, "\(at): aisle")
                if let formatted = want.formatted {
                    XCTAssertEqual(line.formatted, formatted, "\(at): quantity")
                }
                if let sources = want.sources {
                    XCTAssertEqual(line.sourceRecipeIDs.count, sources, "\(at): recipes needing it")
                }
            }

            for absent in scenario.expectAbsent ?? [] {
                XCTAssertFalse(
                    actual.contains { $0.displayName == absent },
                    "\(label): \"\(absent)\" should not be on the list"
                )
            }
        }
    }

    // MARK: - The rules, stated directly

    /// Section 1a: Mealime listed sesame oil twice because it would not add
    /// three tablespoons to two teaspoons. This is that bug, fixed.
    func testTheMealimeDuplicateBug() {
        let oil = Self.candidates.first { $0.name == "sesame oil" }!
        let recipe = { (title: String, quantity: Double, unit: Mise.Unit) in
            RecipeInput(id: UUID(), title: title, baseServings: 4, ingredients: [
                IngredientInput(name: "sesame oil", quantity: quantity, unit: unit, canonicalItemID: oil.id),
            ])
        }
        let list = ListGenerator(matcher: Self.matcher).generate(plan: [
            PlannedMealInput(recipe: recipe("A", 3, .tbsp), servings: 4),
            PlannedMealInput(recipe: recipe("B", 2, .tsp), servings: 4),
        ])

        XCTAssertEqual(list.items.count, 1, "one ingredient, one line")
        XCTAssertEqual(list.items.first?.formatted, "3 2/3 tbsp")
        XCTAssertEqual(list.items.first?.sourceRecipeIDs.count, 2)
    }

    /// Section 5.3 rule 2: what does not resolve still has to land somewhere,
    /// and the user categorises it once.
    func testAnUnknownIngredientLandsInOtherAndIsFlagged() {
        let recipe = RecipeInput(id: UUID(), title: "Experiment", baseServings: 4, ingredients: [
            IngredientInput(name: "dragonfruit powder", quantity: 2, unit: .tbsp),
        ])
        let list = ListGenerator(matcher: Self.matcher).generate(plan: [PlannedMealInput(recipe: recipe, servings: 4)])

        XCTAssertEqual(list.items.first?.aisle, .other)
        XCTAssertEqual(list.items.first?.displayName, "dragonfruit powder")
        XCTAssertTrue(list.items.first?.needsCategorising == true)
        XCTAssertEqual(list.needingCategorising, ["dragonfruit powder"])
    }

    /// Section 4: an optional ingredient is included and marked, not dropped.
    func testOptionalIsMarkedRatherThanDropped() {
        let flakes = Self.candidates.first { $0.name == "red pepper flakes" }!
        let recipe = RecipeInput(id: UUID(), title: "Spicy", baseServings: 4, ingredients: [
            IngredientInput(name: "red pepper flakes", quantity: 1, unit: .tsp, isOptional: true, canonicalItemID: flakes.id),
        ])
        let list = ListGenerator(matcher: Self.matcher).generate(plan: [PlannedMealInput(recipe: recipe, servings: 4)])

        XCTAssertEqual(list.items.count, 1)
        XCTAssertTrue(list.items.first?.isOptional == true)
    }

    /// One recipe needing it makes it needed, however many others call it
    /// optional.
    func testOneRequiredUseMakesItRequired() {
        let flakes = Self.candidates.first { $0.name == "red pepper flakes" }!
        let make = { (optional: Bool) in
            RecipeInput(id: UUID(), title: optional ? "Mild" : "Hot", baseServings: 4, ingredients: [
                IngredientInput(name: "red pepper flakes", quantity: 1, unit: .tsp, isOptional: optional, canonicalItemID: flakes.id),
            ])
        }
        let list = ListGenerator(matcher: Self.matcher).generate(plan: [
            PlannedMealInput(recipe: make(true), servings: 4),
            PlannedMealInput(recipe: make(false), servings: 4),
        ])
        XCTAssertFalse(list.items.first?.isOptional == true)
    }

    // MARK: - Regeneration

    /// Section 4: regenerating preserves check state for unchanged items, and
    /// every manual item.
    func testRegenerationKeepsManualItemsAndUnchangedTicks() {
        let salmon = Self.candidates.first { $0.name == "salmon" }!
        let recipe = RecipeInput(id: UUID(), title: "Salmon", baseServings: 4, ingredients: [
            IngredientInput(name: "salmon", quantity: 1.5, unit: .lb, canonicalItemID: salmon.id),
        ])
        let generator = ListGenerator(matcher: Self.matcher)

        var first = generator.generate(plan: [PlannedMealInput(recipe: recipe, servings: 4)]).items
        first[0].isChecked = true
        let dishSoap = GroceryDraftItem(
            canonicalItemID: nil, displayName: "dish soap", quantities: [Quantity(1)], aisle: .household,
            sourceRecipeIDs: [], isOptional: false, isManual: true, isChecked: false, needsCategorising: false
        )
        first.append(dishSoap)

        let again = generator.generate(plan: [PlannedMealInput(recipe: recipe, servings: 4)], carryingOver: first)

        XCTAssertTrue(
            again.items.contains { $0.isManual && $0.displayName == "dish soap" },
            "a manual item survives regeneration"
        )
        XCTAssertTrue(
            again.items.first { $0.displayName == "salmon" }?.isChecked == true,
            "an unchanged item keeps its tick"
        )
    }

    /// Asked for on 2026-11-01: a hand added item that names something the plan
    /// already produced joins that row instead of sitting beside it.
    func testAManualItemMergesIntoTheRowItNames() {
        let salmon = Self.candidates.first { $0.name == "salmon" }!
        let recipe = RecipeInput(id: UUID(), title: "Salmon", baseServings: 4, ingredients: [
            IngredientInput(name: "salmon", quantity: 1.5, unit: .lb, canonicalItemID: salmon.id),
        ])
        let generator = ListGenerator(matcher: Self.matcher)
        let plan = [PlannedMealInput(recipe: recipe, servings: 4)]

        var first = generator.generate(plan: plan).items
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].formatted, "1 1/2 lb")

        // The user types "1 lb salmon" on a list that already has salmon.
        first[0].quantities = UnitConverter.combine(first[0].quantities + [Quantity(1, .lb)])
        first[0].manualQuantities = [Quantity(1, .lb)]

        let again = generator.generate(plan: plan, carryingOver: first).items
        XCTAssertEqual(again.count, 1, "one row, not two")
        XCTAssertEqual(again[0].formatted, "2 1/2 lb", "the recipe's 1 1/2 lb plus the hand added 1 lb")

        // The crux: regenerating again must not add the hand added pound twice.
        let third = generator.generate(plan: plan, carryingOver: again).items
        XCTAssertEqual(third.count, 1)
        XCTAssertEqual(third[0].formatted, "2 1/2 lb", "the hand added part is added once, not compounded")
    }

    /// A hand added item that matches nothing on the list stays its own row.
    func testAManualItemThatMatchesNothingStaysItsOwnRow() {
        let salmon = Self.candidates.first { $0.name == "salmon" }!
        let recipe = RecipeInput(id: UUID(), title: "Salmon", baseServings: 4, ingredients: [
            IngredientInput(name: "salmon", quantity: 1.5, unit: .lb, canonicalItemID: salmon.id),
        ])
        let generator = ListGenerator(matcher: Self.matcher)
        let plan = [PlannedMealInput(recipe: recipe, servings: 4)]

        var first = generator.generate(plan: plan).items
        first.append(GroceryDraftItem(
            displayName: "dish soap",
            quantities: [Quantity(1)],
            aisle: .household,
            isManual: true,
            manualQuantities: [Quantity(1)]
        ))

        let again = generator.generate(plan: plan, carryingOver: first).items
        XCTAssertEqual(again.count, 2)
        XCTAssertEqual(again.first { $0.displayName == "dish soap" }?.formatted, "1")

        let third = generator.generate(plan: plan, carryingOver: again).items
        XCTAssertEqual(third.count, 2, "it does not multiply across regenerations")
        XCTAssertEqual(third.first { $0.displayName == "dish soap" }?.formatted, "1")
    }

    /// A changed quantity means there is more to buy, so the tick would be a lie.
    func testAChangedQuantityLosesItsTick() {
        let salmon = Self.candidates.first { $0.name == "salmon" }!
        let recipe = RecipeInput(id: UUID(), title: "Salmon", baseServings: 4, ingredients: [
            IngredientInput(name: "salmon", quantity: 1.5, unit: .lb, canonicalItemID: salmon.id),
        ])
        let generator = ListGenerator(matcher: Self.matcher)

        var first = generator.generate(plan: [PlannedMealInput(recipe: recipe, servings: 4)]).items
        first[0].isChecked = true

        let doubled = generator.generate(plan: [PlannedMealInput(recipe: recipe, servings: 8)], carryingOver: first)
        XCTAssertEqual(doubled.items.first?.formatted, "3 lb")
        XCTAssertFalse(doubled.items.first?.isChecked == true, "more to buy means it is not done")
    }

    /// Section 4 keeps the tick on an unchanged line, which is right while
    /// somebody is in the shop adding a meal to the week. A week later it is
    /// the opposite of right.
    func testAFinishedListDoesNotCarryItsTicksIntoTheNextShop() {
        let eggs = Self.candidate("eggs")
        let bread = Self.candidate("sandwich bread")
        let recipe = RecipeInput(id: UUID(), title: "Breakfast", baseServings: 4, ingredients: [
            IngredientInput(name: "eggs", quantity: 6, unit: .count, canonicalItemID: eggs.id),
            IngredientInput(name: "sandwich bread", quantity: 1, unit: .count, canonicalItemID: bread.id),
        ])
        let generator = ListGenerator(matcher: Self.matcher)
        let plan = [PlannedMealInput(recipe: recipe, servings: 4)]

        // Shopped: every line ticked.
        var shopped = generator.generate(plan: plan).items
        XCTAssertEqual(shopped.count, 2)
        for index in shopped.indices { shopped[index].isChecked = true }

        let nextWeek = generator.generate(plan: plan, carryingOver: shopped).items
        XCTAssertEqual(nextWeek.count, 2)
        XCTAssertTrue(
            nextWeek.allSatisfy { !$0.isChecked },
            "a shop that finished is over, so the next list starts from nothing bought"
        )
    }

    /// The other half, which must keep working: a list still being shopped
    /// keeps what has been ticked so far.
    func testAListStillBeingShoppedKeepsItsTicks() {
        let eggs = Self.candidate("eggs")
        let bread = Self.candidate("sandwich bread")
        let recipe = RecipeInput(id: UUID(), title: "Breakfast", baseServings: 4, ingredients: [
            IngredientInput(name: "eggs", quantity: 6, unit: .count, canonicalItemID: eggs.id),
            IngredientInput(name: "sandwich bread", quantity: 1, unit: .count, canonicalItemID: bread.id),
        ])
        let generator = ListGenerator(matcher: Self.matcher)
        let plan = [PlannedMealInput(recipe: recipe, servings: 4)]

        var partly = generator.generate(plan: plan).items
        partly[0].isChecked = true

        let again = generator.generate(plan: plan, carryingOver: partly).items
        XCTAssertEqual(again.filter(\.isChecked).count, 1, "one thing is still in the trolley")
    }

    // MARK: - Shape

    func testSectionsFollowTheHouseholdWalkOrder() {
        let scenario = Self.fixtures.scenarios.first { !$0.expect.isEmpty }!
        let plan = scenario.plan.map { PlannedMealInput(recipe: Self.recipeInput($0.recipe), servings: $0.servings) }
        let list = generator(for: scenario).generate(plan: plan)

        let positions = list.sections.map { Self.canonical.aisleOrder.firstIndex(of: $0.aisle) ?? -1 }
        XCTAssertEqual(positions, positions.sorted(), "sections should follow the store walk order")
        XCTAssertTrue(list.sections.allSatisfy { !$0.items.isEmpty }, "an aisle with nothing in it is not a section")
    }

    func testAnEmptyPlanMakesAnEmptyList() {
        let list = ListGenerator(matcher: Self.matcher).generate(plan: [])
        XCTAssertEqual(list.sections, [])
        XCTAssertEqual(list.items, [])
    }

    // MARK: - Rule 4, the restocking half

    private static func candidate(_ name: String) -> CanonicalCandidate {
        candidates.first { $0.name == name }!
    }

    /// Section 4 says the generator includes `low` and `out`, and for a long
    /// time it only excluded `have`. The pantry could take a row away and never
    /// add one, so a staple nothing happened to call for this week ran out in
    /// silence. That is the one the household notices.
    func testALowStapleNoRecipeAskedForStillReachesTheList() {
        let eggs = Self.candidate("eggs")
        let list = ListGenerator(matcher: Self.matcher, pantryRestock: [eggs.id]).generate(plan: [])

        XCTAssertEqual(list.items.count, 1, "the pantry asked for it, so it is on the list")
        XCTAssertEqual(list.items.first?.displayName, "eggs")
        XCTAssertEqual(list.items.first?.aisle, eggs.aisle, "it shops in its own aisle, not in other")
        XCTAssertFalse(list.items.first?.isOptional == true, "running out is not optional")
        XCTAssertFalse(list.items.first?.isManual == true, "the pantry produced it, not the shopper")
    }

    /// No quantity, on purpose. The plan knows it needs three tablespoons of
    /// oil. Nobody knows how much oil a house needs, and a number invented here
    /// would be a worse answer than none.
    func testARestockedStapleCarriesNoQuantity() {
        let oil = Self.candidate("olive oil")
        let list = ListGenerator(matcher: Self.matcher, pantryRestock: [oil.id]).generate(plan: [])

        XCTAssertEqual(list.items.first?.formatted, "", "buy some, not buy 1")
        XCTAssertEqual(list.items.first?.quantities, [])
    }

    /// The recipe's row says more than the pantry's would, so the pantry does
    /// not add a second one beside it.
    func testARecipeAlreadyAskingForItWins() {
        let eggs = Self.candidate("eggs")
        let recipe = RecipeInput(id: UUID(), title: "Frittata", baseServings: 4, ingredients: [
            IngredientInput(name: "eggs", quantity: 6, unit: .count, canonicalItemID: eggs.id),
        ])
        let list = ListGenerator(matcher: Self.matcher, pantryRestock: [eggs.id])
            .generate(plan: [PlannedMealInput(recipe: recipe, servings: 4)])

        XCTAssertEqual(list.items.count, 1, "one item, one line, however many things asked for it")
        XCTAssertEqual(list.items.first?.formatted, "6", "the amount the cooking needs survives")
    }

    /// `pantryHave` and `pantryRestock` are complementary where the store builds
    /// them, but the generator takes them as given and must not contradict
    /// itself if they ever overlap.
    func testHavingItBeatsRestockingIt() {
        let eggs = Self.candidate("eggs")
        let recipe = RecipeInput(id: UUID(), title: "Frittata", baseServings: 4, ingredients: [
            IngredientInput(name: "eggs", quantity: 6, unit: .count, canonicalItemID: eggs.id),
        ])
        let list = ListGenerator(matcher: Self.matcher, pantryHave: [eggs.id], pantryRestock: [eggs.id])
            .generate(plan: [PlannedMealInput(recipe: recipe, servings: 4)])

        XCTAssertEqual(list.items, [], "we have them, so nothing to buy")
    }

    /// A pantry entry can outlive the canonical item it points at. That is a
    /// blank row on the hero screen if it is not caught here.
    func testAnUnknownRestockIDIsIgnored() {
        let list = ListGenerator(matcher: Self.matcher, pantryRestock: [UUID()]).generate(plan: [])
        XCTAssertEqual(list.items, [])
    }

    func testRestockedStaplesShopInTheWalkOrder() {
        let order = Self.canonical.aisleOrder
        let list = ListGenerator(
            matcher: Self.matcher,
            pantryRestock: [Self.candidate("eggs").id, Self.candidate("cucumber").id, Self.candidate("olive oil").id],
            aisleOrder: order
        ).generate(plan: [])

        XCTAssertEqual(list.items.count, 3)
        let positions = list.sections.map { order.firstIndex(of: $0.aisle) ?? -1 }
        XCTAssertEqual(positions, positions.sorted(), "restocking walks the shop like everything else")
    }
}
