import Foundation
import XCTest
@testable import Mise

/// The seed loader's idempotency rests entirely on these being stable, so this
/// checks the implementation against the published RFC 4122 test vector rather
/// than only against itself.
final class StableIDTests: XCTestCase {
    /// RFC 4122 appendix: version 5 of the DNS namespace with the name
    /// "www.example.org".
    func testMatchesThePublishedVersion5Vector() {
        let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let id = StableID.uuid(namespace: dns, name: "www.example.org")
        XCTAssertEqual(id.uuidString, "74738FF5-5367-5958-9AEE-98FFFDCD1876")
    }

    func testTheMiseNamespaceIsVersion5OfItsDomain() {
        let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        XCTAssertEqual(StableID.uuid(namespace: dns, name: "mise.benkleiman.com"), StableID.namespace)
    }

    func testTheSameKeyAlwaysGivesTheSameID() {
        XCTAssertEqual(
            StableID.canonicalItem(name: "kosher salt"),
            StableID.canonicalItem(name: "kosher salt")
        )
        XCTAssertEqual(
            StableID.recipe(seedID: "seed-sheet-pan-salmon"),
            StableID.recipe(seedID: "seed-sheet-pan-salmon")
        )
    }

    func testDifferentKindsOfKeyDoNotCollide() {
        XCTAssertNotEqual(StableID.canonicalItem(name: "salmon"), StableID.recipe(seedID: "salmon"))
        XCTAssertNotEqual(
            StableID.ingredient(recipeSeedID: "r", position: 0),
            StableID.step(recipeSeedID: "r", position: 0)
        )
        XCTAssertNotEqual(
            StableID.ingredient(recipeSeedID: "r", position: 0),
            StableID.ingredient(recipeSeedID: "r", position: 1)
        )
    }

    func testEveryGeneratedIDIsAVersion5UUID() {
        let id = StableID.household()
        // Byte 6 high nibble is the version, byte 8 top two bits are the variant.
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        XCTAssertEqual(bytes[6] & 0xF0, 0x50)
        XCTAssertEqual(bytes[8] & 0xC0, 0x80)
    }

    // MARK: - The ids two phones have to agree on

    /// Built in this machine's own calendar rather than from a fixed instant.
    ///
    /// Six hours after a given moment is the same day in Denver and the next
    /// day in New York, so a test written against an epoch constant passes or
    /// fails by where the simulator thinks it is. The thing under test is a
    /// calendar day, so the fixture has to be one too.
    private var monday: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_793_923_200))
    }

    func testTheWeekIsTheSameOnBothPhones() {
        let household = StableID.household()
        XCTAssertEqual(
            StableID.mealPlan(householdID: household, weekStartDate: monday),
            StableID.mealPlan(householdID: household, weekStartDate: monday)
        )
    }

    /// Both phones compute the week start themselves, within the same day but
    /// not to the same instant.
    func testTheWeekIsTheSameAtAnyTimeOfThatDay() {
        let household = StableID.household()
        let laterThatDay = monday.addingTimeInterval(60 * 60 * 6)

        XCTAssertEqual(
            StableID.day(monday), StableID.day(laterThatDay),
            "the key is the calendar day, not the instant"
        )
        XCTAssertEqual(
            StableID.mealPlan(householdID: household, weekStartDate: monday),
            StableID.mealPlan(householdID: household, weekStartDate: laterThatDay)
        )
    }

    func testADifferentWeekIsADifferentPlan() {
        let household = StableID.household()
        XCTAssertNotEqual(
            StableID.mealPlan(householdID: household, weekStartDate: monday),
            StableID.mealPlan(householdID: household, weekStartDate: monday.addingTimeInterval(7 * 86_400))
        )
    }

    /// Surprising, and worth pinning down, because it is what the tie break
    /// exists for: two lines that merged onto one grocery item are the same
    /// line whatever either of them happens to be called.
    func testALineKeysOnItsGroceryItemAndNotOnItsName() {
        let list = UUID()
        let lemon = UUID()
        XCTAssertEqual(
            StableID.groceryItem(listID: list, canonicalItemID: lemon, displayName: "lemons"),
            StableID.groceryItem(listID: list, canonicalItemID: lemon, displayName: "2 lemons, halved")
        )
    }

    /// Which is exactly why the tie break cannot be smuggled into the name. A
    /// caller that varied the name to break a tie would be handed the same id
    /// back every time and spin forever. One did.
    func testTheTieBreakChangesTheIDEvenThoughTheNameDoesNot() {
        let list = UUID()
        let lemon = UUID()
        let first = StableID.groceryItem(listID: list, canonicalItemID: lemon, displayName: "lemons")
        var seen: Set<UUID> = [first]

        for tieBreak in 1...5 {
            let next = StableID.groceryItem(
                listID: list, canonicalItemID: lemon, displayName: "lemons", tieBreak: tieBreak
            )
            XCTAssertFalse(seen.contains(next), "tie break \(tieBreak) repeated an earlier id")
            seen.insert(next)
        }
    }

    func testAHandWrittenLineKeysOnItsName() {
        let list = UUID()
        XCTAssertEqual(
            StableID.groceryItem(listID: list, canonicalItemID: nil, displayName: "Paper Towels"),
            StableID.groceryItem(listID: list, canonicalItemID: nil, displayName: "  paper towels  "),
            "both phones have to land on the same line for the same thing typed"
        )
    }

    func testOneListPerHousehold() {
        XCTAssertEqual(
            StableID.groceryList(householdID: StableID.household()),
            StableID.groceryList(householdID: StableID.household())
        )
        XCTAssertNotEqual(
            StableID.groceryList(householdID: StableID.household()),
            StableID.groceryList(householdID: StableID.household(key: "other"))
        )
    }
}
