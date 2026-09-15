import Foundation

/// Section 3 asks for an observable store per feature. This is the Phase 0b
/// version: it reads the library through the repository so the view holds no
/// logic, and grows into the search, filter and sort work in Phase 1.
@MainActor
@Observable
final class RecipesStore {
    private let recipes: any RecipeRepository

    private(set) var items: [Recipe] = []
    private(set) var loadProblem: String?

    init(recipes: any RecipeRepository) {
        self.recipes = recipes
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
