import Foundation

/// Section 3 asks for an observable store per feature. This reads the library
/// through the repository so the view holds no logic, and does the one piece of
/// filtering the first usable version needs: a search field.
///
/// Collections, tags and the facet chips from section 5.1 are still to come.
@MainActor
@Observable
final class RecipesStore {
    private let recipes: any RecipeRepository

    private(set) var items: [Recipe] = []
    private(set) var loadProblem: String?

    /// What the user typed in the search field.
    var query: String = ""

    init(recipes: any RecipeRepository) {
        self.recipes = recipes
    }

    /// Every word typed has to appear somewhere in the recipe, rather than the
    /// whole phrase appearing as one run of characters.
    ///
    /// Found on 2026-11-01: searching "lemon past" returned nothing while
    /// "Lemon Garlic Butter Pasta" sat in the list, because no title contains
    /// the literal string "lemon past". People type the words they remember,
    /// not the title, and they stop typing halfway through a word.
    ///
    /// Title, summary, tags and ingredient names are all searched, because
    /// "what can I make with chicken" is a question people actually ask.
    var visible: [Recipe] {
        let terms = Self.terms(in: query)
        guard !terms.isEmpty else { return items }

        return items.filter { recipe in
            let haystack = Self.searchText(for: recipe)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// Split on anything that is not a letter or a digit, so "lemon, garlic"
    /// and "lemon garlic" behave the same.
    private static func terms(in query: String) -> [String] {
        query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func searchText(for recipe: Recipe) -> String {
        var parts = [recipe.title, recipe.summary]
        parts.append(contentsOf: recipe.tags)
        parts.append(contentsOf: recipe.ingredients.map(\.name))
        return parts.joined(separator: " ").lowercased()
    }

    func load() {
        do {
            items = try recipes.all().sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            loadProblem = nil
        } catch {
            items = []
            loadProblem = "The recipe library could not be read. \(error)"
        }
    }
}
