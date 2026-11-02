import XCTest
@testable import Mise

/// Section 5.7's paste a link. Parsing is separated from fetching so the
/// awkward cases are tests rather than a site that has to be live to try.
final class RecipeWebImporterTests: XCTestCase {

    private func page(_ json: String, around body: String = "<p>words</p>") -> String {
        """
        <!doctype html><html><head>
        <script type="application/javascript">var x = {"@type":"Recipe","name":"not this one"}</script>
        <script type="application/ld+json">\(json)</script>
        </head><body>\(body)</body></html>
        """
    }

    private let simple = """
    { "@type": "Recipe", "name": "Lemon Pasta", "description": "Quick.",
      "recipeYield": "4 servings", "totalTime": "PT20M",
      "recipeIngredient": ["1 pound spaghetti", "2 garlic cloves, sliced"],
      "recipeInstructions": [{"@type":"HowToStep","text":"Boil the pasta."}] }
    """

    // MARK: - Finding it

    func testARecipeIsReadOutOfAPage() throws {
        let recipe = try XCTUnwrap(RecipeWebImporter.parse(html: page(simple), from: URL(string: "https://example.com/r/1")))
        XCTAssertEqual(recipe.title, "Lemon Pasta")
        XCTAssertEqual(recipe.baseServings, 4)
        XCTAssertEqual(recipe.ingredientLines, ["1 pound spaghetti", "2 garlic cloves, sliced"])
        XCTAssertEqual(recipe.steps, ["Boil the pasta."])
        XCTAssertEqual(recipe.sourceURL, "https://example.com/r/1")
    }

    func testOnlyLdJsonBlocksAreRead() {
        // The page above also contains a plain javascript block with a Recipe
        // shaped object in it, which is not the contract.
        let recipe = RecipeWebImporter.parse(html: page(simple), from: nil)
        XCTAssertEqual(recipe?.title, "Lemon Pasta")
    }

    func testARecipeInsideAGraphIsFound() throws {
        let graph = """
        { "@context":"https://schema.org",
          "@graph":[{"@type":"WebSite","name":"A food blog"},
                    {"@type":"Recipe","name":"Buried","recipeIngredient":["salt"],"recipeInstructions":["Stir."]}] }
        """
        let recipe = try XCTUnwrap(RecipeWebImporter.parse(html: page(graph), from: nil))
        XCTAssertEqual(recipe.title, "Buried", "most content management systems publish it this way")
    }

    func testAnArrayOfTypesStillCounts() throws {
        let both = """
        { "@type": ["Recipe","NewsArticle"], "name": "Both", "recipeIngredient": ["salt"], "recipeInstructions": ["Stir."] }
        """
        XCTAssertEqual(try XCTUnwrap(RecipeWebImporter.parse(html: page(both), from: nil)).title, "Both")
    }

    func testAPageWithNoRecipeReturnsNothingRatherThanScraping() {
        let article = """
        { "@type": "NewsArticle", "name": "Ten best pasta shapes", "articleBody": "1 pound spaghetti" }
        """
        XCTAssertNil(
            RecipeWebImporter.parse(html: page(article), from: nil),
            "scraping the body would produce something that looks like a recipe and is not"
        )
        XCTAssertNil(RecipeWebImporter.parse(html: "<html><body>nothing here</body></html>", from: nil))
        XCTAssertNil(RecipeWebImporter.parse(html: page("{ not json }"), from: nil))
    }

    // MARK: - Reading the pieces

    func testDurations() {
        XCTAssertEqual(RecipeWebImporter.minutes(from: "PT1H30M"), 90)
        XCTAssertEqual(RecipeWebImporter.minutes(from: "PT25M"), 25)
        XCTAssertEqual(RecipeWebImporter.minutes(from: "P1DT2H"), 1560)
        XCTAssertEqual(RecipeWebImporter.minutes(from: "PT1H"), 60)
        XCTAssertEqual(RecipeWebImporter.minutes(from: "nonsense"), 0)
        XCTAssertEqual(RecipeWebImporter.minutes(from: nil), 0)
    }

    func testATotalWithNoBreakdownIsNotCountedTwice() throws {
        let timed = """
        { "@type":"Recipe","name":"T","prepTime":"PT5M","totalTime":"PT20M",
          "recipeIngredient":["salt"],"recipeInstructions":["Stir."] }
        """
        let recipe = try XCTUnwrap(RecipeWebImporter.parse(html: page(timed), from: nil))
        XCTAssertEqual(recipe.prepMinutes, 5)
        XCTAssertEqual(recipe.cookMinutes, 15, "prep plus cook equals the total the site published")
    }

    func testServings() {
        XCTAssertEqual(RecipeWebImporter.servings(from: "4 servings"), 4)
        XCTAssertEqual(RecipeWebImporter.servings(from: "4 to 6 servings"), 4)
        XCTAssertEqual(RecipeWebImporter.servings(from: ["8"]), 8)
        XCTAssertEqual(RecipeWebImporter.servings(from: NSNumber(value: 6)), 6)
        XCTAssertEqual(RecipeWebImporter.servings(from: "Serves a crowd"), 4, "the same guess the file importers make, and correctable")
    }

    func testInstructionsComeOutFlatWhicheverShapeTheyArriveIn() {
        XCTAssertEqual(RecipeWebImporter.instructions(["One.", "Two."]), ["One.", "Two."])
        XCTAssertEqual(RecipeWebImporter.instructions([["@type": "HowToStep", "text": "One."]]), ["One."])
        XCTAssertEqual(
            RecipeWebImporter.instructions([
                ["@type": "HowToSection", "itemListElement": [["text": "One."], ["text": "Two."]]],
                "Three.",
            ]),
            ["One.", "Two.", "Three."]
        )
    }

    func testMarkupInsideTheJSONIsTakenOut() {
        XCTAssertEqual(RecipeWebImporter.clean("<p>Heat the oven to 425&deg;</p>"), "Heat the oven to 425&deg;")
        XCTAssertEqual(RecipeWebImporter.clean("a&nbsp;&amp;&nbsp;b"), "a & b")
        XCTAssertEqual(RecipeWebImporter.clean("  spaced   out \n lines "), "spaced out lines")
        XCTAssertEqual(RecipeWebImporter.clean("&frac12; cup"), "1/2 cup")
    }

    // MARK: - Bad input

    func testSomethingThatIsNotAnAddressIsRefusedBeforeAnyRequest() async {
        for typed in ["", "not a url", "hello world"] {
            do {
                _ = try await RecipeWebImporter.load(typed)
                XCTFail("\(typed) should have been refused")
            } catch {
                XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
            }
        }
    }
}
