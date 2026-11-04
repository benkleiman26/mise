import XCTest
import SwiftData
@testable import Mise

/// The week's plan and the grocery list used to take a fresh random id each
/// time a phone made one, so two phones never merged them: each kept its own
/// and showed whichever the database handed back first.
@MainActor
final class DuplicateReconcilerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var households: SwiftDataHouseholdRepository!
    private var mealPlans: SwiftDataMealPlanRepository!
    private var groceryLists: SwiftDataGroceryListRepository!
    private var reconciler: DuplicateReconciler!

    private let householdID = StableID.household()
    private let monday = Date(timeIntervalSince1970: 1_793_923_200)

    override func setUp() async throws {
        try await super.setUp()
        container = try MiseSchema.makeContainer(inMemory: true)
        context = ModelContext(container)
        households = SwiftDataHouseholdRepository(context: context)
        mealPlans = SwiftDataMealPlanRepository(context: context)
        groceryLists = SwiftDataGroceryListRepository(context: context)

        households.insert(Household(id: householdID, name: "Test"))
        try households.save()

        reconciler = DuplicateReconciler(
            households: households, mealPlans: mealPlans, groceryLists: groceryLists
        )
    }

    override func tearDown() async throws {
        reconciler = nil
        groceryLists = nil
        mealPlans = nil
        households = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    private var canonicalPlanID: UUID {
        StableID.mealPlan(householdID: householdID, weekStartDate: monday)
    }

    private var canonicalListID: UUID {
        StableID.groceryList(householdID: householdID)
    }

    @discardableResult
    private func plan(id: UUID = UUID()) -> MealPlan {
        let plan = MealPlan(id: id, householdID: householdID, weekStartDate: monday)
        mealPlans.insert(plan)
        return plan
    }

    @discardableResult
    private func meal(_ plan: MealPlan, recipe: UUID, slot: MealSlot = .dinner) -> PlannedMeal {
        let meal = PlannedMeal(
            householdID: householdID,
            position: plan.entries.count,
            date: monday,
            slot: slot,
            recipeID: recipe,
            servings: 4,
            isCooked: false
        )
        meal.plan = plan
        plan.entries.append(meal)
        return meal
    }

    @discardableResult
    private func list(id: UUID = UUID(), generatedAt: Date = .now) -> GroceryList {
        let list = GroceryList(id: id, householdID: householdID, generatedAt: generatedAt)
        groceryLists.insert(list)
        return list
    }

    @discardableResult
    private func item(
        _ list: GroceryList, _ name: String, canonical: UUID? = nil, isChecked: Bool = false
    ) -> GroceryItem {
        let row = GroceryItem(
            householdID: householdID,
            position: list.items.count,
            canonicalItemID: canonical,
            displayName: name,
            isChecked: isChecked
        )
        row.list = list
        list.items.append(row)
        return row
    }

    private var tombstones: [Deletion] {
        (try? context.fetch(FetchDescriptor<Deletion>())) ?? []
    }

    // MARK: - The week

    func testTwoWeeksForOneWeekBecomeOne() throws {
        let mine = plan()
        let hers = plan()
        meal(mine, recipe: UUID())
        meal(hers, recipe: UUID())

        let report = try reconciler.run()

        let plans = try mealPlans.all()
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.id, canonicalPlanID,
                       "under the id both phones now compute, so they meet next time")
        XCTAssertEqual(plans.first?.entries.count, 2, "neither phone loses its meals")
        XCTAssertEqual(report.plansMerged, 2)
    }

    func testTheSameMealPlannedOnBothPhonesIsOneMeal() throws {
        let recipe = UUID()
        let mine = plan()
        let hers = plan()
        meal(mine, recipe: recipe)
        meal(hers, recipe: recipe)

        try reconciler.run()

        XCTAssertEqual(try mealPlans.all().first?.entries.count, 1,
                       "the same recipe in the same slot on the same day is one dinner")
    }

    func testTheSameRecipeInADifferentSlotIsADifferentMeal() throws {
        let recipe = UUID()
        let mine = plan()
        let hers = plan()
        meal(mine, recipe: recipe, slot: .dinner)
        meal(hers, recipe: recipe, slot: .lunch)

        try reconciler.run()

        XCTAssertEqual(try mealPlans.all().first?.entries.count, 2)
    }

    /// One phone with one plan still has to move, or it keeps its old id
    /// forever and never meets the other phone's.
    func testALonePlanIsMovedToTheDerivedID() throws {
        let only = plan()
        meal(only, recipe: UUID())

        try reconciler.run()

        let plans = try mealPlans.all()
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.id, canonicalPlanID)
        XCTAssertEqual(plans.first?.entries.count, 1)
    }

    func testAPlanAlreadyUnderTheDerivedIDIsLeftAlone() throws {
        let already = plan(id: canonicalPlanID)
        meal(already, recipe: UUID())

        let report = try reconciler.run()

        XCTAssertTrue(report.didNothing)
        XCTAssertEqual(try mealPlans.all().count, 1)
    }

    /// A cascade takes the row out of the store without telling the other
    /// phone, which then puts it straight back.
    func testEveryRemovedRecordLeavesATombstone() throws {
        let stray = plan()
        meal(stray, recipe: UUID())

        try reconciler.run()

        let gone = Set(tombstones.map(\.kind))
        XCTAssertTrue(gone.contains(.mealPlan), "the stray week")
        XCTAssertTrue(gone.contains(.plannedMeal), "and the meal that was on it")
    }

    // MARK: - The list

    func testTwoListsBecomeOne() throws {
        let lemon = UUID()
        let mine = list(generatedAt: Date(timeIntervalSince1970: 100))
        let hers = list(generatedAt: Date(timeIntervalSince1970: 200))
        item(mine, "lemons", canonical: lemon)
        item(hers, "lemons", canonical: lemon)
        item(hers, "paper towels")

        let report = try reconciler.run()

        let lists = try groceryLists.all()
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.id, canonicalListID)
        XCTAssertEqual(
            Set(lists.first?.items.map(\.displayName) ?? []),
            ["lemons", "paper towels"],
            "one line per thing to buy, not one per phone"
        )
        XCTAssertEqual(report.listsMerged, 2)
    }

    func testAnItemTickedOnOnlyOnePhoneStaysOnTheList() throws {
        let milk = UUID()
        let mine = list(generatedAt: Date(timeIntervalSince1970: 100))
        let hers = list(generatedAt: Date(timeIntervalSince1970: 200))
        item(mine, "milk", canonical: milk, isChecked: true)
        item(hers, "milk", canonical: milk, isChecked: false)

        try reconciler.run()

        let row = try XCTUnwrap(groceryLists.all().first?.items.first)
        XCTAssertFalse(row.isChecked,
                       "getting this the other way round sends somebody home without the milk")
    }

    func testTwoHandWrittenItemsWithTheSameNameMerge() throws {
        let mine = list(generatedAt: Date(timeIntervalSince1970: 100))
        let hers = list(generatedAt: Date(timeIntervalSince1970: 200))
        item(mine, "paper towels")
        item(hers, "paper towels")

        try reconciler.run()

        XCTAssertEqual(try groceryLists.all().first?.items.count, 1)
    }

    func testALoneListIsMovedToTheDerivedID() throws {
        let only = list()
        item(only, "lemons", canonical: UUID())

        try reconciler.run()

        let lists = try groceryLists.all()
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.id, canonicalListID)
        XCTAssertEqual(lists.first?.items.count, 1)
    }

    // MARK: - Running again

    func testASecondRunDoesNothing() throws {
        let mine = plan()
        meal(mine, recipe: UUID())
        let shopping = list()
        item(shopping, "lemons", canonical: UUID())

        let first = try reconciler.run()
        XCTAssertFalse(first.didNothing)

        let second = try reconciler.run()
        XCTAssertTrue(second.didNothing, "it runs on every launch for the rest of the app's life")
    }

    func testNothingHappensWithoutAHousehold() throws {
        for household in try households.all() { households.delete(household) }
        try households.save()

        XCTAssertTrue(try reconciler.run().didNothing)
    }
}
