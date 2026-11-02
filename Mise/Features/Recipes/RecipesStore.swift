import Foundation

/// Section 5.1's library screen.
///
/// 427 recipes in one alphabetical list is worse than no list: the answer to
/// "what are we eating on Thursday" is in there and cannot be found. So this
/// holds the search, the facets and the sort, and the view holds none of it.
@MainActor
@Observable
final class RecipesStore {
    enum Sort: String, CaseIterable, Identifiable {
        case title, quickest, mostCooked, recentlyAdded
        var id: String { rawValue }

        var label: String {
            switch self {
            case .title: "A to Z"
            case .quickest: "Quickest first"
            case .mostCooked: "Cooked most"
            case .recentlyAdded: "Added recently"
            }
        }
    }

    /// A time limit, in the sizes a weeknight actually comes in.
    enum TimeLimit: Int, CaseIterable, Identifiable {
        case twenty = 20, thirty = 30, fortyFive = 45
        var id: Int { rawValue }
        var label: String { "Under \(rawValue) min" }
    }

    private let recipes: any RecipeRepository

    private(set) var items: [Recipe] = []
    private(set) var loadProblem: String?

    var query: String = ""
    var selectedTags: Set<String> = []
    var onlyFavourites = false
    var onlyCooked = false
    var timeLimit: TimeLimit?
    var sort: Sort = .title

    init(recipes: any RecipeRepository) {
        self.recipes = recipes
    }

    var hasFilters: Bool {
        !selectedTags.isEmpty || onlyFavourites || onlyCooked || timeLimit != nil
    }

    func clearFilters() {
        selectedTags = []
        onlyFavourites = false
        onlyCooked = false
        timeLimit = nil
    }

    /// Every tag in the library with how many recipes carry it, most used
    /// first. These are the NYT folders and the Mealime collections, which came
    /// across with the imports and are the closest thing to how the household
    /// already thinks about its recipes.
    var tags: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for recipe in items {
            for tag in Set(recipe.tags.map { $0.trimmingCharacters(in: .whitespaces) }) where !tag.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    /// Every word typed has to appear somewhere in the recipe, rather than the
    /// whole phrase appearing as one run of characters.
    ///
    /// Found on 2026-11-01: searching "lemon past" returned nothing while
    /// "Lemon Garlic Butter Pasta" sat in the list. People type the words they
    /// remember, not the title, and they stop typing halfway through a word.
    var visible: [Recipe] {
        let terms = Self.terms(in: query)

        let filtered = items.filter { recipe in
            if onlyFavourites, !recipe.isFavorite { return false }
            if onlyCooked, recipe.timesCooked == 0 { return false }
            if let limit = timeLimit {
                // A recipe with no time recorded is not known to be quick, and
                // 159 of the owner's have none. Claiming them would make the
                // filter a lie.
                guard recipe.totalMinutes > 0, recipe.totalMinutes <= limit.rawValue else { return false }
            }
            if !selectedTags.isEmpty {
                // Every chosen tag has to be on it. Narrowing is what a second
                // tap means.
                let own = Set(recipe.tags.map { $0.lowercased() })
                guard selectedTags.allSatisfy({ own.contains($0.lowercased()) }) else { return false }
            }
            guard !terms.isEmpty else { return true }
            let haystack = Self.searchText(for: recipe)
            return terms.allSatisfy { haystack.contains($0) }
        }

        return filtered.sorted(by: order)
    }

    private var order: (Recipe, Recipe) -> Bool {
        switch sort {
        case .title:
            return { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .quickest:
            // Unknown times go last rather than first, since zero would sort
            // them to the top and they are the least known, not the quickest.
            return { left, right in
                let a = left.totalMinutes == 0 ? Int.max : left.totalMinutes
                let b = right.totalMinutes == 0 ? Int.max : right.totalMinutes
                if a != b { return a < b }
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
        case .mostCooked:
            return { left, right in
                if left.timesCooked != right.timesCooked { return left.timesCooked > right.timesCooked }
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
        case .recentlyAdded:
            return { $0.createdAt > $1.createdAt }
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
            items = try recipes.all()
            loadProblem = nil
        } catch {
            items = []
            loadProblem = "The recipe library could not be read. \(error)"
        }
    }

    func toggleFavourite(_ recipe: Recipe) {
        do {
            recipe.isFavorite.toggle()
            recipe.updatedAt = .now
            try recipes.save()
        } catch {
            loadProblem = "That could not be saved. \(error)"
        }
    }
}
