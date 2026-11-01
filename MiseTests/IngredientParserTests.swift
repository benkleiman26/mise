import XCTest
@testable import Mise

/// IngredientParser, driven from `Fixtures/ingredient_parsing.json` and from
/// every ingredient line in the seed library.
///
/// The fixture holds the awkward shapes: unicode fractions, ranges, package
/// sizes in brackets, optional markers, lines with no quantity at all, and the
/// section 1a example Mealime could not handle. `tools/resource-lint` checks
/// that each case is self consistent, so the expectations here were reviewed
/// before any of this compiled.
///
/// The seed round trip is the other half. Rendering a real ingredient and
/// parsing it back must return what it started as, across all 379 lines, which
/// catches the cases nobody thought to write down.
final class IngredientParserTests: XCTestCase {

    // MARK: - Fixtures

    private struct Fixtures: Decodable {
        struct Case: Decodable {
            let input: String
            let quantity: Double?
            let unit: Unit?
            let name: String
            let preparation: String?
            let parenthetical: String?
            let isOptional: Bool?
            let confidence: ParseConfidence
            let why: String?
        }
        let cases: [Case]
    }

    private static let fixtures: Fixtures = {
        let bundle = Bundle(for: IngredientParserTests.self)
        guard let url = bundle.url(forResource: "ingredient_parsing", withExtension: "json") else {
            fatalError("ingredient_parsing.json is not in the test bundle. Check that MiseTests/Fixtures is in the test target's resources.")
        }
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }()

    func testCorpus() {
        for entry in Self.fixtures.cases {
            let parsed = IngredientParser.parse(entry.input)
            let label = entry.why.map { "\(entry.input)  (\($0))" } ?? entry.input

            if let expected = entry.quantity {
                guard let actual = parsed.quantity else {
                    XCTFail("\(label): expected quantity \(expected), got none")
                    continue
                }
                XCTAssertEqual(actual, expected, accuracy: 0.01, "\(label): quantity")
            } else {
                XCTAssertNil(parsed.quantity, "\(label): expected no quantity")
            }

            XCTAssertEqual(parsed.unit, entry.unit, "\(label): unit")
            XCTAssertEqual(parsed.name, entry.name, "\(label): name")
            XCTAssertEqual(parsed.preparation, entry.preparation, "\(label): preparation")
            XCTAssertEqual(parsed.parenthetical, entry.parenthetical, "\(label): parenthetical")
            XCTAssertEqual(parsed.isOptional, entry.isOptional ?? false, "\(label): isOptional")
            XCTAssertEqual(parsed.confidence, entry.confidence, "\(label): confidence")
        }
    }

    /// Section 1a's own example, called out because it is the line that made
    /// Mealime's grocery list worse than it needed to be.
    func testTheLineMealimeCouldNotHandle() {
        let parsed = IngredientParser.parse("1 bunch (about 1 pound) asparagus, tough ends removed and stalks cut into 1/2-inch pieces")
        XCTAssertEqual(parsed.quantity, 1)
        XCTAssertEqual(parsed.unit, .bunch)
        XCTAssertEqual(parsed.name, "asparagus", "this is the part that has to reach the grocery list")
        XCTAssertEqual(parsed.parenthetical, "about 1 pound")
        XCTAssertEqual(parsed.confidence, .high)
    }

    // MARK: - Round trip over the real seed library

    private struct SeedFile: Decodable {
        struct Recipe: Decodable {
            let id: String
            let title: String
            let ingredients: [Ingredient]
        }
        struct Ingredient: Decodable {
            let name: String
            let quantity: Double?
            let unit: Unit?
        }
        let recipes: [Recipe]
    }

    private static let seed: SeedFile = {
        guard let url = MiseBundle.resources.url(forResource: "seed_recipes", withExtension: "json") else {
            fatalError("seed_recipes.json is not in the app bundle")
        }
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(SeedFile.self, from: Data(contentsOf: url))
    }()

    /// Render every seeded ingredient the way a recipe would write it, parse it
    /// back, and insist on getting the same thing out.
    ///
    /// The seed data is ground truth that exists for its own reasons, so this
    /// is not the parser grading its own homework.
    func testEverySeedIngredientSurvivesARoundTrip() {
        var checked = 0

        for recipe in Self.seed.recipes {
            for ingredient in recipe.ingredients {
                let amount = UnitConverter.format(Measurement(ingredient.quantity ?? 1, ingredient.unit))
                let line = amount.isEmpty ? ingredient.name : "\(amount) \(ingredient.name)"
                let parsed = IngredientParser.parse(line)
                let label = "\(recipe.title): \"\(line)\""

                if let expected = ingredient.quantity {
                    XCTAssertEqual(parsed.quantity ?? .nan, expected, accuracy: 0.02, "\(label): quantity")
                }

                // A line like "2 eggs" carries no unit word, which is exactly
                // what `count` means, so the two are the same answer.
                XCTAssertEqual(parsed.unit ?? .count, ingredient.unit ?? .count, "\(label): unit")

                // Preparation comes back either after a comma, as the seed
                // writes it, or ahead of the name when a participle led it.
                let rebuilt: [String]
                if let preparation = parsed.preparation {
                    rebuilt = ["\(parsed.name), \(preparation)", "\(preparation) \(parsed.name)"]
                } else {
                    rebuilt = [parsed.name]
                }
                XCTAssertTrue(
                    rebuilt.contains(ingredient.name),
                    "\(label): came back as \(rebuilt) rather than \"\(ingredient.name)\""
                )

                checked += 1
            }
        }

        XCTAssertEqual(checked, 379, "the seed library should still have 379 ingredient lines")
    }

    /// Confidence is what decides whether a line interrupts the user, so a
    /// clean seed line must never be flagged.
    func testSeedLinesParseConfidently() {
        var flagged: [String] = []

        for recipe in Self.seed.recipes {
            for ingredient in recipe.ingredients {
                let amount = UnitConverter.format(Measurement(ingredient.quantity ?? 1, ingredient.unit))
                let line = amount.isEmpty ? ingredient.name : "\(amount) \(ingredient.name)"
                if IngredientParser.parse(line).confidence == .low { flagged.append(line) }
            }
        }

        XCTAssertEqual(flagged, [], "no seed line should need a human to look at it")
    }

    // MARK: - Properties worth holding regardless of the examples

    func testParsingNeverThrowsAwayTheLine() {
        for entry in Self.fixtures.cases {
            XCTAssertEqual(IngredientParser.parse(entry.input).raw, entry.input, "the original has to survive for the review screen")
        }
    }

    func testParsingIsStable() {
        for entry in Self.fixtures.cases {
            let once = IngredientParser.parse(entry.input)
            let twice = IngredientParser.parse(entry.input)
            XCTAssertEqual(once, twice, "parsing the same line twice must agree")
        }
    }

    func testEmptyAndJunkLines() {
        for line in ["", "   ", ",", "()"] {
            let parsed = IngredientParser.parse(line)
            XCTAssertEqual(parsed.confidence, .low, "\"\(line)\" should be flagged rather than accepted")
            XCTAssertNil(parsed.quantity)
        }
    }

    func testConfidenceOnlyEverFalls() {
        // A line with several doubts at once lands on the lowest of them, not
        // the last one checked.
        let parsed = IngredientParser.parse("1-2 cups chopped salt and pepper")
        XCTAssertEqual(parsed.confidence, .low, "a range, a leading participle and two items should give the worst answer")
    }

    func testEveryUnitSpellingResolves() {
        for (spelling, expected) in IngredientParser.unitSpellings {
            let parsed = IngredientParser.parse("2 \(spelling) flour")
            XCTAssertEqual(parsed.unit, expected, "\"2 \(spelling) flour\" should read as \(expected.rawValue)")
            XCTAssertEqual(parsed.name, "flour", "\"\(spelling)\" should not be left in the name")
        }
    }
}
