import XCTest
@testable import Mise

/// What kind of dish a recipe is. Asked for on 2026-11-02: the imported tags
/// are the owner's own NYT folders and Mealime collections, and "what are we
/// in the mood for" is a different question.
final class DishTypeClassifierTests: XCTestCase {

    private func kinds(_ title: String, ingredients: [String] = [], steps: [String] = []) -> [DishType] {
        DishTypeClassifier.classify(title: title, ingredients: ingredients, steps: steps)
    }

    // MARK: - The title decides

    func testTheObviousOnes() {
        XCTAssertEqual(kinds("Lemon Garlic Butter Pasta"), [.pasta])
        XCTAssertEqual(kinds("Sheet Pan Salmon and Green Beans"), [.sheetPan])
        XCTAssertEqual(kinds("Chicken Noodle Soup"), [.noodles, .soup])
        XCTAssertEqual(kinds("Burrito Bowls"), [.bowl])
        XCTAssertEqual(kinds("Black Bean Quesadillas"), [.taco])
        XCTAssertEqual(kinds("Shakshuka"), [.eggs])
    }

    func testPunctuationAndHyphensDoNotMatter() {
        XCTAssertEqual(kinds("Sheet-Pan Chicken"), [.sheetPan])
        XCTAssertEqual(kinds("One-Pan Orzo"), kinds("One Pan Orzo"))
    }

    func testAWordInsideAnotherWordIsNotAMatch() {
        XCTAssertFalse(kinds("Pastrami Sandwich").contains(.pasta), "pastrami is not pasta")
        XCTAssertFalse(kinds("Eggplant Parmesan").contains(.eggs), "eggplant is not eggs")
    }

    // MARK: - The method counts for less

    func testASuggestionInTheMethodDoesNotDecideTheDish() {
        let result = kinds(
            "Garlic Butter Chicken Thighs",
            steps: ["Serve with pasta if you like."]
        )
        XCTAssertFalse(result.contains(.pasta), "one mention away from the title is a serving suggestion")
    }

    func testTheMethodCanDecideWhenItSaysSoTwice() {
        let result = kinds(
            "Salmon and Green Beans",
            steps: ["Heat the oven to 425.", "Spread everything on a rimmed baking sheet.", "Use a sheet pan if you have one."]
        )
        XCTAssertTrue(result.contains(.sheetPan), "the method says what it is even when the title does not")
    }

    // MARK: - More than one, but not many

    func testADishCanBeTwoThings() {
        XCTAssertEqual(kinds("Baked Ziti"), [.pasta])
        let gratin = kinds("Potato and Leek Gratin")
        XCTAssertTrue(gratin.contains(.bake))
    }

    func testAPlainlyOneThingDishDoesNotCollectWeakerLabels() {
        let result = kinds(
            "Spaghetti Bolognese",
            ingredients: ["olive oil", "white beans", "rice vinegar"],
            steps: ["Roast the tomatoes first."]
        )
        XCTAssertEqual(result, [.pasta], "pasta first, and the rest is detail")
    }

    func testThreeLabelsIsTheCeiling() {
        let result = kinds("Grilled Chicken Taco Salad Bowls with Roasted Rice and Beans")
        XCTAssertLessThanOrEqual(result.count, 3, "a description, not a word cloud")
    }

    // MARK: - Saying nothing

    func testNothingFitsRatherThanGuessing() {
        XCTAssertTrue(kinds("Tuesday").isEmpty)
        XCTAssertTrue(kinds("").isEmpty)
        XCTAssertTrue(
            kinds("Something Nice").isEmpty,
            "an empty answer is honest; a wrong facet sends the cook looking in the wrong place"
        )
    }

    // MARK: - Every type is reachable

    func testEveryDishTypeHasAName() {
        for kind in DishType.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind.rawValue) has no name")
            XCTAssertFalse(kind.systemImage.isEmpty, "\(kind.rawValue) has no icon")
        }
    }
}
