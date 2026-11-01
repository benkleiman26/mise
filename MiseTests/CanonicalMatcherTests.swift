import XCTest
@testable import Mise

/// CanonicalMatcher, driven from `Fixtures/canonical_matching.json` and from
/// the real canonical item table.
///
/// `tools/resource-lint` checks every case in that fixture against
/// `canonical_items.json`: the item exists, it is in the aisle claimed, and the
/// stated rung of the ladder is the rung it actually matches on. So these
/// expectations were reviewed before any of this compiled.
final class CanonicalMatcherTests: XCTestCase {

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
    }

    private struct Fixtures: Decodable {
        struct Case: Decodable {
            let input: String
            let item: String?
            let aisle: Aisle
            let reason: MatchReason
            let confidence: ParseConfidence
            let why: String?
        }
        struct Learned: Decodable {
            let input: String
            let teach: String
            let item: String
            let aisle: Aisle
            let why: String?
        }
        let cases: [Case]
        let learnedAliases: [Learned]
    }

    private static func load<T: Decodable>(_ type: T.Type, _ resource: String, from bundle: Bundle) -> T {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            fatalError("\(resource).json is not in the bundle. Check the target's resources.")
        }
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private static let candidates: [CanonicalCandidate] = {
        let file = load(CanonicalFile.self, "canonical_items", from: MiseBundle.resources)
        return file.items.map {
            CanonicalCandidate(
                id: StableID.canonicalItem(name: $0.name),
                name: $0.name,
                aliases: $0.aliases ?? [],
                aisle: $0.aisle,
                isStaple: $0.isStaple ?? false,
                defaultUnit: $0.defaultUnit
            )
        }
    }()

    private static let fixtures = load(Fixtures.self, "canonical_matching", from: Bundle(for: CanonicalMatcherTests.self))
    private static let matcher = CanonicalMatcher(items: candidates)

    private struct SeedFile: Decodable {
        struct Recipe: Decodable {
            let title: String
            let ingredients: [Ingredient]
        }
        struct Ingredient: Decodable {
            let name: String
            let canonicalItem: String?
        }
        let recipes: [Recipe]
    }

    private static let seed = load(SeedFile.self, "seed_recipes", from: MiseBundle.resources)

    // MARK: - The corpus

    func testCorpus() {
        for entry in Self.fixtures.cases {
            let match = Self.matcher.match(entry.input)
            let label = entry.why.map { "\"\(entry.input)\"  (\($0))" } ?? "\"\(entry.input)\""

            XCTAssertEqual(match.item?.name, entry.item, "\(label): item")
            XCTAssertEqual(match.aisle, entry.aisle, "\(label): aisle")
            XCTAssertEqual(match.reason, entry.reason, "\(label): reason")
            XCTAssertEqual(match.confidence, entry.confidence, "\(label): confidence")
        }
    }

    /// The trap a containment rule falls into without a head noun check. If
    /// this ever passes as milk, someone comes home with the wrong thing.
    func testMilkChocolateIsNotMilk() {
        let match = Self.matcher.match("milk chocolate")
        XCTAssertNil(match.item)
        XCTAssertEqual(match.aisle, .other, "section 5.3 sends an unmatched ingredient to other")
        XCTAssertTrue(match.needsReview)
    }

    /// Section 4's own example of a written-out name resolving to an item.
    func testSpecExampleResolves() {
        let match = Self.matcher.match("boneless skinless chicken thighs")
        XCTAssertEqual(match.item?.name, "chicken thighs")
        XCTAssertEqual(match.reason, .alias)
        XCTAssertFalse(match.needsReview)
    }

    // MARK: - The real table

    /// Section 5.1 requires every seed recipe to have canonical item links set
    /// so the list generator works on first launch. This is that requirement as
    /// a test, over all 379 lines.
    func testEverySeedIngredientResolvesToTheItemTheSeedDataNames() {
        var checked = 0
        var failures: [String] = []

        for recipe in Self.seed.recipes {
            for ingredient in recipe.ingredients {
                guard let expected = ingredient.canonicalItem else { continue }
                // The matcher sees what the parser produced, which is the name
                // without its trailing preparation.
                let name = ingredient.name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ingredient.name
                let match = Self.matcher.match(name.trimmingCharacters(in: .whitespaces))
                checked += 1

                guard let resolved = match.item else {
                    failures.append("\(recipe.title): \"\(name)\" resolved to nothing, expected \"\(expected)\"")
                    continue
                }
                if resolved.name != expected {
                    failures.append("\(recipe.title): \"\(name)\" resolved to \"\(resolved.name)\", expected \"\(expected)\"")
                }
            }
        }

        XCTAssertEqual(failures, [], "every seeded ingredient must resolve")
        XCTAssertEqual(checked, 379, "the seed library should still have 379 ingredient lines")
    }

    func testNoSeedIngredientNeedsReview() {
        var flagged: [String] = []
        for recipe in Self.seed.recipes {
            for ingredient in recipe.ingredients {
                let name = ingredient.name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ingredient.name
                if Self.matcher.match(name.trimmingCharacters(in: .whitespaces)).needsReview {
                    flagged.append("\(recipe.title): \(name)")
                }
            }
        }
        XCTAssertEqual(flagged, [], "a shipped recipe should never interrupt the user on first launch")
    }

    func testEveryCanonicalNameAndAliasResolvesToItself() {
        for candidate in Self.candidates {
            let byName = Self.matcher.match(candidate.name)
            XCTAssertEqual(byName.item?.id, candidate.id, "\"\(candidate.name)\" should find itself")
            XCTAssertEqual(byName.reason, .exactName, "\"\(candidate.name)\"")

            for alias in candidate.aliases {
                let byAlias = Self.matcher.match(alias)
                XCTAssertEqual(byAlias.item?.id, candidate.id, "alias \"\(alias)\" of \"\(candidate.name)\"")
                XCTAssertFalse(byAlias.needsReview, "alias \"\(alias)\" should resolve confidently")
            }
        }
    }

    // MARK: - Teaching

    /// Section 5.3: the user categorises an unmatched item once, and that
    /// teaches the alias table.
    func testTeachingAnAlias() {
        for entry in Self.fixtures.learnedAliases {
            let before = Self.matcher.match(entry.input)
            XCTAssertNil(before.item, "\"\(entry.input)\" should not match before it is taught")

            guard let target = Self.candidates.first(where: { $0.name == entry.item }) else {
                XCTFail("the fixture names an item that does not exist: \(entry.item)")
                continue
            }

            let taught = Self.matcher.teaching(entry.input, as: target.id)
            let after = taught.match(entry.input)
            XCTAssertEqual(after.item?.id, target.id, "\"\(entry.input)\" should resolve once taught")
            XCTAssertEqual(after.reason, .learned)
            XCTAssertFalse(after.needsReview, "something the user chose is not worth asking about again")
        }
    }

    func testTeachingDoesNotDisturbTheOriginalMatcher() {
        guard let salt = Self.candidates.first(where: { $0.name == "kosher salt" }) else {
            return XCTFail("kosher salt should be in the table")
        }
        _ = Self.matcher.teaching("fleur de sel", as: salt.id)
        XCTAssertNil(Self.matcher.match("fleur de sel").item, "teaching returns a new matcher rather than mutating this one")
    }

    func testTeachingAccumulates() {
        guard let salt = Self.candidates.first(where: { $0.name == "kosher salt" }),
              let oil = Self.candidates.first(where: { $0.name == "olive oil" })
        else { return XCTFail("the table should have both") }

        let taught = Self.matcher
            .teaching("fleur de sel", as: salt.id)
            .teaching("huile d olive", as: oil.id)

        XCTAssertEqual(taught.match("fleur de sel").item?.id, salt.id, "the first lesson should survive the second")
        XCTAssertEqual(taught.match("huile d olive").item?.id, oil.id)
    }

    // MARK: - Shape

    func testEmptyAndWhitespaceResolveToNothing() {
        for input in ["", "   ", ",,,"] {
            let match = Self.matcher.match(input)
            XCTAssertNil(match.item, "\"\(input)\"")
            XCTAssertEqual(match.reason, .none)
            XCTAssertEqual(match.aisle, .other)
        }
    }

    func testBatchMatchingAgreesWithOneAtATime() {
        let names = Self.fixtures.cases.map(\.input)
        XCTAssertEqual(Self.matcher.match(all: names), names.map(Self.matcher.match))
    }
}
