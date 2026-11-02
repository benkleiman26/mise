import XCTest
import SwiftData
@testable import Mise

/// Section 5.4. A pantry status seeded once at install and never changeable
/// means the list quietly leaves out eggs forever whether or not there are any.
@MainActor
final class PantryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var pantry: SwiftDataPantryRepository!
    private var canonicalItems: SwiftDataCanonicalItemRepository!
    private var households: SwiftDataHouseholdRepository!
    private var store: PantryStore!
    private let householdID = StableID.household()

    override func setUp() async throws {
        try await super.setUp()
        container = try MiseSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        pantry = SwiftDataPantryRepository(context: context)
        canonicalItems = SwiftDataCanonicalItemRepository(context: context)
        households = SwiftDataHouseholdRepository(context: context)

        households.insert(Household(id: householdID, name: "Test"))
        try households.save()

        store = PantryStore(pantry: pantry, canonicalItems: canonicalItems, households: households)
    }

    override func tearDown() async throws {
        store = nil
        pantry = nil
        canonicalItems = nil
        households = nil
        container = nil
        try await super.tearDown()
    }

    @discardableResult
    private func item(_ name: String, aisle: Aisle = .produce) -> CanonicalItem {
        let item = CanonicalItem(householdID: householdID, name: name, aisle: aisle)
        canonicalItems.insert(item)
        try? canonicalItems.save()
        return item
    }

    private func track(_ item: CanonicalItem, _ status: PantryStatus) {
        pantry.insert(PantryEntry(householdID: householdID, canonicalItemID: item.id, status: status))
        try? pantry.save()
    }

    private var rows: [PantryStore.Row] { store.groups.flatMap(\.rows) }

    // MARK: - What is shown

    func testOnlyWhatTheHouseholdTracksIsShownByDefault() {
        let salt = item("kosher salt", aisle: .bakingAndSpices)
        item("dragonfruit")
        track(salt, .have)
        store.load()

        XCTAssertEqual(rows.map(\.name), ["kosher salt"],
                       "395 items would bury the twenty that are tracked")
    }

    func testEverythingCanBeShownOnPurpose() {
        item("kosher salt", aisle: .bakingAndSpices)
        item("dragonfruit")
        store.showsEverything = true
        store.load()

        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.status == nil }, "untracked is not the same as out")
    }

    func testSearchReachesItemsThatAreNotTracked() {
        item("dragonfruit")
        store.query = "dragon"
        store.load()

        XCTAssertEqual(rows.map(\.name), ["dragonfruit"],
                       "an item has to be findable before it can be tracked")
    }

    func testSearchMatchesAnAliasToo() {
        let item = item("scallions")
        item.aliases = ["green onions"]
        try? canonicalItems.save()

        store.query = "green onion"
        store.load()
        XCTAssertEqual(rows.map(\.name), ["scallions"])
    }

    // MARK: - Changing it

    func testSayingYouAreOutOfSomethingUntrackedStartsTrackingIt() throws {
        item("eggs", aisle: .dairyAndEggs)
        store.showsEverything = true
        store.load()

        store.set(.out, for: try XCTUnwrap(rows.first))

        XCTAssertEqual(try pantry.all().count, 1)
        XCTAssertEqual(try pantry.all().first?.status, .out)
    }

    func testChangingAStatusKeepsOneRecordRatherThanAddingAnother() throws {
        let eggs = item("eggs", aisle: .dairyAndEggs)
        track(eggs, .have)
        store.load()

        store.set(.low, for: try XCTUnwrap(rows.first))
        store.set(.out, for: try XCTUnwrap(rows.first))

        XCTAssertEqual(try pantry.all().count, 1)
        XCTAssertEqual(try pantry.all().first?.status, .out)
    }

    /// Four states, not three. An item nobody has said anything about must not
    /// be treated as one deliberately marked out, or the list buys it weekly.
    func testUntrackingDeletesTheRecordRatherThanInventingAState() throws {
        let eggs = item("eggs", aisle: .dairyAndEggs)
        track(eggs, .have)
        store.load()

        store.set(nil, for: try XCTUnwrap(rows.first))

        XCTAssertTrue(try pantry.all().isEmpty)
        store.load()
        XCTAssertTrue(store.isEmpty, "and it drops out of the tracked list")
    }

    func testTheChangeIsVisibleImmediately() throws {
        let eggs = item("eggs", aisle: .dairyAndEggs)
        track(eggs, .have)
        store.load()

        store.set(.out, for: try XCTUnwrap(rows.first))
        XCTAssertEqual(rows.first?.status, .out, "the screen reloads itself rather than waiting for a revisit")
    }

    // MARK: - The point of it

    /// Section 4: the generator excludes `have` and includes `low` and `out`.
    func testWhatTheGeneratorSeesAfterAChange() throws {
        let eggs = item("eggs", aisle: .dairyAndEggs)
        track(eggs, .have)
        store.load()

        var excluded = Set(try pantry.all().filter { $0.status == .have }.map(\.canonicalItemID))
        XCTAssertTrue(excluded.contains(eggs.id), "while they have eggs, eggs stay off the list")

        store.set(.out, for: try XCTUnwrap(rows.first))

        excluded = Set(try pantry.all().filter { $0.status == .have }.map(\.canonicalItemID))
        XCTAssertFalse(excluded.contains(eggs.id), "once they are out, eggs reach the list again")
    }
}
