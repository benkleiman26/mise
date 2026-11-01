import XCTest
@testable import Mise

/// Section 5.7. The owner's rescued Mealime library arrives as ingredient lines
/// written the way people write them, so the import is only as good as the
/// parser and the matcher behind it. These check the seam between them.
final class RecipeImporterTests: XCTestCase {

    private static let candidates: [CanonicalCandidate] = [
        CanonicalCandidate(id: UUID(), name: "scallions", aliases: ["green onions"], aisle: .produce),
        CanonicalCandidate(id: UUID(), name: "olive oil", aisle: .oilsAndCondiments, isStaple: true),
        CanonicalCandidate(id: UUID(), name: "cucumber", aliases: ["cucumbers"], aisle: .produce),
        CanonicalCandidate(id: UUID(), name: "kosher salt", aisle: .bakingAndSpices, isStaple: true),
    ]

    private var importer: RecipeImporter {
        RecipeImporter(householdID: UUID(), matcher: CanonicalMatcher(items: Self.candidates))
    }

    private func document(_ recipes: String) -> Data {
        Data("""
        { "format": "mise-recipe-import", "version": 1, "source": "mealime", "recipes": [\(recipes)] }
        """.utf8)
    }

    // MARK: - Reading the file

    func testAFileFromAnotherToolIsRefusedRatherThanHalfImported() {
        let data = Data(#"{ "format": "something-else", "version": 1, "recipes": [] }"#.utf8)
        XCTAssertThrowsError(try RecipeImporter.decode(data)) { error in
            guard case RecipeImporter.ImportError.unexpectedFormat(let found) = error else {
                return XCTFail("expected an unexpectedFormat error, got \(error)")
            }
            XCTAssertEqual(found, "something-else")
        }
    }

    func testRubbishIsRefusedWithSomethingReadable() {
        XCTAssertThrowsError(try RecipeImporter.decode(Data("not json".utf8))) { error in
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }

    // MARK: - Building a recipe

    func testAnIngredientLineIsParsedAndMatched() throws {
        let data = document("""
        {
          "externalID": "abc",
          "title": "Cucumber Salad",
          "baseServings": 2,
          "cookMinutes": 0,
          "ingredientLines": ["2 scallions, trimmed then sliced", "2 tbsp olive oil"],
          "steps": ["Slice everything.", "Toss."]
        }
        """)
        let parsed = try RecipeImporter.decode(data)
        var report = RecipeImporter.Report()
        let recipe = importer.build(parsed.recipes[0], source: "mealime", into: &report)

        XCTAssertEqual(recipe.title, "Cucumber Salad")
        XCTAssertEqual(recipe.baseServings, 2)
        XCTAssertEqual(recipe.sourceType, .imported)
        XCTAssertEqual(recipe.externalIDs["mealime"], "abc")
        XCTAssertEqual(recipe.orderedSteps.map(\.text), ["Slice everything.", "Toss."])

        let scallions = try XCTUnwrap(recipe.orderedIngredients.first)
        XCTAssertEqual(scallions.quantity, 2)
        XCTAssertEqual(scallions.name, "scallions")
        XCTAssertEqual(scallions.preparation, "trimmed then sliced")
        XCTAssertEqual(scallions.aisle, .produce)
        XCTAssertNotNil(scallions.canonicalItemID, "it should resolve to the canonical item")

        let oil = recipe.orderedIngredients[1]
        XCTAssertEqual(oil.quantity, 2)
        XCTAssertEqual(oil.unit, Mise.Unit.tbsp)
        XCTAssertEqual(oil.aisle, .oilsAndCondiments)

        XCTAssertEqual(report.ingredientsRead, 2)
        XCTAssertTrue(report.unmatchedIngredients.isEmpty)
    }

    func testAnIngredientThatMatchesNothingStillImportsAndIsReported() throws {
        let data = document("""
        { "title": "Mystery", "ingredientLines": ["1 cup nduja"], "steps": [] }
        """)
        let parsed = try RecipeImporter.decode(data)
        var report = RecipeImporter.Report()
        let recipe = importer.build(parsed.recipes[0], source: "mealime", into: &report)

        let ingredient = try XCTUnwrap(recipe.orderedIngredients.first)
        XCTAssertEqual(ingredient.name, "nduja", "it is still on the recipe")
        XCTAssertNil(ingredient.canonicalItemID)
        XCTAssertEqual(ingredient.aisle, .other, "section 5.3: unmatched lands in other")
        XCTAssertEqual(report.unmatchedIngredients, ["nduja"])
    }

    func testALineWithNoQuantityKeepsItsName() throws {
        let data = document("""
        { "title": "Salad", "ingredientLines": ["Kosher salt"], "steps": [] }
        """)
        let parsed = try RecipeImporter.decode(data)
        var report = RecipeImporter.Report()
        let recipe = importer.build(parsed.recipes[0], source: "mealime", into: &report)

        let salt = try XCTUnwrap(recipe.orderedIngredients.first)
        XCTAssertNil(salt.quantity)
        XCTAssertEqual(salt.name.lowercased(), "kosher salt")
        XCTAssertNotNil(salt.canonicalItemID)
    }

    // MARK: - Importing twice

    func testTheSameRecipeImportsToTheSameID() throws {
        let data = document("""
        { "externalID": "abc", "title": "Cucumber Salad", "ingredientLines": ["1 cucumber"], "steps": [] }
        """)
        let first = try RecipeImporter.decode(data).recipes[0]
        let second = try RecipeImporter.decode(data).recipes[0]

        let importer = self.importer
        XCTAssertEqual(
            importer.id(for: first, source: "mealime"),
            importer.id(for: second, source: "mealime"),
            "importing the same library twice must update rather than duplicate"
        )
    }

    func testTwoRecipesWithoutExternalIDsAreToldApartByTitle() throws {
        let data = document("""
        { "title": "Toast", "ingredientLines": ["bread"], "steps": [] },
        { "title": "Soup", "ingredientLines": ["water"], "steps": [] }
        """)
        let parsed = try RecipeImporter.decode(data)
        let importer = self.importer
        XCTAssertNotEqual(
            importer.id(for: parsed.recipes[0], source: "mealime"),
            importer.id(for: parsed.recipes[1], source: "mealime")
        )
    }

    func testAnImportedIDNeverCollidesWithASeededOne() throws {
        let data = document("""
        { "externalID": "seed-sheet-pan-salmon", "title": "Not the seed one", "ingredientLines": ["salt"], "steps": [] }
        """)
        let imported = try RecipeImporter.decode(data).recipes[0]
        XCTAssertNotEqual(
            importer.id(for: imported, source: "mealime"),
            StableID.recipe(seedID: "seed-sheet-pan-salmon"),
            "an import must not overwrite a built in recipe that happens to share a key"
        )
    }

    // MARK: - Missing fields

    func testMissingFieldsFallBackRatherThanFailing() throws {
        let data = document("""
        { "title": "Bare", "ingredientLines": [], "steps": ["Do the thing."] }
        """)
        let parsed = try RecipeImporter.decode(data)
        var report = RecipeImporter.Report()
        let recipe = importer.build(parsed.recipes[0], source: "mealime", into: &report)

        XCTAssertEqual(recipe.baseServings, 4)
        XCTAssertEqual(recipe.cookMinutes, 0)
        XCTAssertEqual(recipe.prepMinutes, 0)
        XCTAssertEqual(recipe.summary, "")
        XCTAssertNil(recipe.sourceURL)
        XCTAssertTrue(recipe.tags.isEmpty)
    }

    func testANonsenseServingCountIsClampedRatherThanTrusted() throws {
        let data = document("""
        { "title": "Zero", "baseServings": 0, "timesCooked": -3, "ingredientLines": ["salt"], "steps": [] }
        """)
        let parsed = try RecipeImporter.decode(data)
        var report = RecipeImporter.Report()
        let recipe = importer.build(parsed.recipes[0], source: "mealime", into: &report)

        XCTAssertEqual(recipe.baseServings, 1, "dividing by zero servings would take the list with it")
        XCTAssertEqual(recipe.timesCooked, 0)
    }
}
