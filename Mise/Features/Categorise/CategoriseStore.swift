import Foundation

/// Section 5.3 rule 2: an ingredient that resolves to nothing is flagged, the
/// user says what it is once, and the table knows it from then on.
///
/// This is what ends the loop of sending lists of unmatched names to be fixed
/// in the resource file. The owner's first import left 344 of them, and four
/// rounds of editing the table by hand got it to 52. The last ones are
/// genuinely odd and nobody but the cook knows what they meant.
@MainActor
@Observable
final class CategoriseStore {
    /// One name to categorise, and how many ingredient rows are waiting on it.
    struct Pending: Identifiable, Equatable {
        let name: String
        let count: Int
        /// The recipes it appears in, for deciding what it meant.
        let recipes: [String]
        var id: String { name }
    }

    private let recipes: any RecipeRepository
    private let canonicalItems: any CanonicalItemRepository

    private(set) var pending: [Pending] = []
    private(set) var items: [CanonicalItem] = []
    private(set) var problem: String?
    /// What the last teaching did, for a confirmation the user can read.
    private(set) var lastTaught: String?

    var query: String = ""

    init(recipes: any RecipeRepository, canonicalItems: any CanonicalItemRepository) {
        self.recipes = recipes
        self.canonicalItems = canonicalItems
    }

    var isEmpty: Bool { pending.isEmpty }

    /// Grocery items to choose from, filtered by the search field. Word by
    /// word, so "chick pea" finds canned chickpeas the way search does on the
    /// recipes screen.
    var choices: [CanonicalItem] {
        let terms = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            let haystack = ([item.name, item.aisle.displayName] + item.aliases + item.learnedAliases)
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    func load() {
        do {
            items = try canonicalItems.all()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            var counts: [String: Int] = [:]
            var sources: [String: Set<String>] = [:]
            for ingredient in try recipes.uncategorisedIngredients() {
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                counts[name, default: 0] += 1
                if let title = ingredient.recipe?.title {
                    sources[name, default: []].insert(title)
                }
            }

            pending = counts
                .map { Pending(name: $0.key, count: $0.value, recipes: Array(sources[$0.key] ?? []).sorted()) }
                .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            problem = nil
        } catch {
            pending = []
            problem = "The uncategorized ingredients could not be read. \(error)"
        }
    }

    /// Teaches the table that `name` means `item`, and applies it to every
    /// ingredient already waiting on it.
    ///
    /// The phrase goes in `learnedAliases`, which seeding never overwrites.
    func teach(_ name: String, as item: CanonicalItem) {
        let phrase = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }

        do {
            if !item.learnedAliases.contains(where: { $0.caseInsensitiveCompare(phrase) == .orderedSame }) {
                item.learnedAliases.append(phrase)
                item.updatedAt = .now
            }

            // Everything already in the library that was waiting on this name,
            // matched the same way the matcher would have. Without this the
            // user teaches the table and the list still says Other until the
            // next import.
            let key = CanonicalMatcher.normalize(phrase)
            var applied = 0
            for ingredient in try recipes.uncategorisedIngredients()
            where CanonicalMatcher.normalize(ingredient.name) == key {
                ingredient.canonicalItemID = item.id
                ingredient.aisle = item.aisle
                ingredient.updatedAt = .now
                applied += 1
            }

            try canonicalItems.save()
            try recipes.save()

            lastTaught = applied == 1
                ? "\(phrase) is \(item.name), on 1 recipe"
                : "\(phrase) is \(item.name), on \(applied) recipes"
            load()
        } catch {
            problem = "That could not be saved. \(error)"
        }
    }
}
