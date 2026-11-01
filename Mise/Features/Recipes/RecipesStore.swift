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

    /// Title first, then the tags, then the ingredient names, because "what can
    /// I make with chicken" is the question people actually ask.
    var visible: [Recipe] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }

        return items.filter { recipe in
            if recipe.title.localizedCaseInsensitiveContains(needle) { return true }
            if recipe.tags.contains(where: { $0.localizedCaseInsensitiveContains(needle) }) { return true }
            return recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(needle) }
        }
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
