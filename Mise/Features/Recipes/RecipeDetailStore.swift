import Foundation

/// The one thing the recipe screen changes: how many the recipe is written for.
///
/// Mealime leaves `serving_count` empty on a recipe you typed in yourself, and
/// 159 of the owner's 213 arrived that way and were given four. Four is a
/// reasonable guess and a guess is what it is, so it has to be correctable.
/// Everything downstream scales off that number: the plan, and through it the
/// grocery list.
@MainActor
@Observable
final class RecipeDetailStore {
    private let recipes: any RecipeRepository

    private(set) var problem: String?

    init(recipes: any RecipeRepository) {
        self.recipes = recipes
    }

    /// Hearts a recipe, from the screen that is open when somebody decides.
    ///
    /// The list has had a swipe for this since the beginning and the detail
    /// screen has had nothing, so the only way to mark a favourite was a
    /// gesture with no sign it exists, performed on a row rather than on the
    /// recipe you are actually reading.
    func toggleFavourite(_ recipe: Recipe) {
        do {
            recipe.isFavorite.toggle()
            recipe.updatedAt = .now
            try recipes.save()
            problem = nil
        } catch {
            problem = "That could not be saved. \(error)"
        }
    }

    /// Says what the written amounts are for, without touching the amounts.
    ///
    /// This is a correction, not a conversion: "these quantities feed two, not
    /// four". Rewriting the ingredients to match would destroy what the recipe
    /// actually says, which is the one thing imported text has going for it.
    func setBaseServings(_ servings: Int, on recipe: Recipe) {
        guard servings > 0, servings != recipe.baseServings else { return }
        do {
            recipe.baseServings = servings
            recipe.updatedAt = .now
            try recipes.save()
            problem = nil
        } catch {
            problem = "That could not be saved. \(error)"
        }
    }
}
