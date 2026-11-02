import Foundation
import XCTest
@testable import Mise

/// The resource files decide where every grocery item lands and they fail
/// quietly, so these assertions are the app side companion to
/// `tools/resource-lint`.
final class SeedCatalogTests: XCTestCase {
    private var catalog: SeedCatalog!

    override func setUpWithError() throws {
        try super.setUpWithError()
        catalog = try SeedCatalog.load()
    }

    override func tearDown() {
        catalog = nil
        super.tearDown()
    }

    func testBothResourceFilesAreInTheBundle() throws {
        XCTAssertFalse(catalog.canonicalItems.isEmpty)
        XCTAssertFalse(catalog.recipes.isEmpty)
    }

    /// The table is meant to grow: every unmatched ingredient in a real import
    /// is a gap in it. Asserting today's number would fail the next time it is
    /// filled in, which is the opposite of what this test is for. What matters
    /// is that it is big enough to cover a real library and that `tools/resource-lint`
    /// has passed over it, which the lint step in CI checks properly.
    func testTheCanonicalItemTableIsBigEnoughToBeTheRealOne() {
        XCTAssertGreaterThanOrEqual(
            catalog.canonicalItems.count,
            297,
            "the table has shrunk below the version that was first checked"
        )
        XCTAssertFalse(catalog.canonicalItems.filter(\.isStaple).isEmpty)
        XCTAssertTrue(
            catalog.canonicalItems.allSatisfy { !$0.name.isEmpty },
            "every item needs a name to be shoppable"
        )
    }

    func testTheSeedLibraryLoads() {
        // Section 5.1 asks for 40 to 60 starter recipes. Asserting the range
        // rather than today's number means adding a recipe does not fail a test
        // that was never about the exact count.
        XCTAssertTrue(
            (40...60).contains(catalog.recipes.count),
            "section 5.1 asks for 40 to 60 seed recipes, the library has \(catalog.recipes.count)"
        )
        XCTAssertTrue(catalog.recipes.allSatisfy { $0.sourceType == .builtIn })
    }

    /// Section 5.1: every seed ingredient must link to a canonical item so the
    /// grocery list works out of the box.
    func testEveryIngredientResolvesToACanonicalItem() {
        let unresolved = catalog.unresolvedIngredients()
        XCTAssertTrue(
            unresolved.isEmpty,
            "Unresolved: " + unresolved.map { "\($0.recipe) -> \($0.reference)" }.joined(separator: ", ")
        )
    }

    /// Section 5.5: a step that names an ingredient the recipe does not list
    /// would show a blank line in cook mode.
    func testEveryStepReferencePointsAtAnIngredientTheRecipeLists() {
        let unresolved = catalog.unresolvedStepReferences()
        XCTAssertTrue(
            unresolved.isEmpty,
            "Unresolved: " + unresolved.map { "\($0.recipe) step \($0.step) -> \($0.reference)" }.joined(separator: ", ")
        )
    }

    /// `Recipe.totalMinutes` is computed from prep plus cook, so the number
    /// written in the file has to agree or the app would show a different time
    /// from the one the recipe was written with.
    func testWrittenTotalMinutesAgreesWithPrepPlusCook() {
        for recipe in catalog.recipes {
            XCTAssertEqual(
                recipe.totalMinutes,
                recipe.prepMinutes + recipe.cookMinutes,
                "\(recipe.id) disagrees about its total time"
            )
        }
    }

    func testTheAisleOrderCoversEveryAisleExactlyOnce() {
        XCTAssertEqual(catalog.aisleOrder.count, Aisle.allCases.count)
        XCTAssertEqual(Set(catalog.aisleOrder), Set(Aisle.allCases))
    }

    func testNamesAndAliasesShareOneNamespaceWithNoCollisions() {
        var seen = Set<String>()
        for item in catalog.canonicalItems {
            for text in [item.name] + item.aliases {
                XCTAssertTrue(seen.insert(SeedCatalog.key(text)).inserted, "\"\(text)\" is claimed twice")
            }
        }
    }

    func testAWrongFormatIsRejectedRatherThanHalfLoaded() throws {
        let canonical = Data(#"{"format":"something-else","version":1,"aisleOrder":[],"items":[]}"#.utf8)
        let recipes = Data(#"{"format":"seed-recipes","version":1,"recipes":[]}"#.utf8)
        XCTAssertThrowsError(try SeedCatalog(canonicalItemsData: canonical, seedRecipesData: recipes))
    }
}
