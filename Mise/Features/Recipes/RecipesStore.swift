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
    var selectedKinds: Set<DishType> = []
    var onlyFavourites = false
    var onlyCooked = false
    /// The standbys, as their own control rather than one collection among
    /// forty. They answer a different question from the rest of the library:
    /// not what kind of dish this is, but whether it is one of the handful
    /// worth reaching for on a night that was going to end in a takeout
    /// order. See STANDBYS.md.
    var onlyStandbys = false
    var timeLimit: TimeLimit?
    var sort: Sort = .title

    init(recipes: any RecipeRepository) {
        self.recipes = recipes
    }

    static let standbyTag = "standby"

    /// What is currently narrowing the list, in words.
    ///
    /// A sheet holds the controls, which keeps the top of the screen calm and
    /// hides the state. So the state comes back out here, under the row, where
    /// "19 of 447" on its own would not say why.
    var filterSummary: String {
        var parts: [String] = []
        if onlyStandbys { parts.append("Standbys") }
        if onlyFavourites { parts.append("Favorites") }
        if onlyCooked { parts.append("Cooked before") }
        if let limit = timeLimit { parts.append(limit.label.lowercased()) }
        parts.append(contentsOf: selectedKinds
            .map(\.displayName)
            .sorted())
        parts.append(contentsOf: selectedTags.sorted())
        return parts.joined(separator: " · ")
    }

    /// How many separate choices are on, for the badge on the button.
    var filterCount: Int {
        var n = selectedKinds.count + selectedTags.count
        if onlyFavourites { n += 1 }
        if onlyCooked { n += 1 }
        if timeLimit != nil { n += 1 }
        return n
    }

    var hasFilters: Bool {
        !selectedTags.isEmpty || !selectedKinds.isEmpty || onlyFavourites || onlyCooked
            || onlyStandbys || timeLimit != nil
    }

    func clearFilters() {
        selectedTags = []
        selectedKinds = []
        onlyFavourites = false
        onlyCooked = false
        onlyStandbys = false
        timeLimit = nil
    }

    /// Every dish type present in the library, with counts, in the order the
    /// enum declares rather than by popularity, so the row does not reshuffle
    /// itself as the library grows.
    var kinds: [(kind: DishType, count: Int)] {
        var counts: [DishType: Int] = [:]
        for recipe in items {
            for kind in Set(recipe.kinds) { counts[kind, default: 0] += 1 }
        }
        return DishType.allCases.compactMap { kind in
            guard let count = counts[kind], count > 0 else { return nil }
            return (kind: kind, count: count)
        }
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
            if onlyStandbys, !recipe.tags.contains(where: { $0.caseInsensitiveCompare(Self.standbyTag) == .orderedSame }) {
                return false
            }
            if let limit = timeLimit {
                // A recipe with no time recorded is not known to be quick, and
                // 159 of the owner's have none. Claiming them would make the
                // filter a lie.
                guard recipe.totalMinutes > 0, recipe.totalMinutes <= limit.rawValue else { return false }
            }
            if !selectedKinds.isEmpty {
                // Any of the chosen kinds, not all: "pasta or soup" is what
                // picking two of these means, since a dish is rarely both and
                // asking for both would always come back empty.
                let own = Set(recipe.kinds)
                guard !own.isDisjoint(with: selectedKinds) else { return false }
            }
            if !selectedTags.isEmpty {
                // Every chosen tag has to be on it. Narrowing is what a second
                // tap means.
                let own = Set(recipe.tags.map { $0.lowercased() })
                guard selectedTags.allSatisfy({ own.contains($0.lowercased()) }) else { return false }
            }
            return true
        }

        guard !terms.isEmpty else { return filtered.sorted(by: order) }

        // Ranked, not filtered alphabetically.
        //
        // Searching used to join the title, the summary, the tags and every
        // ingredient name into one string and ask whether it contained the
        // word. So "chicken" returned every recipe holding chicken broth, and
        // the four hundred results came back A to Z, with no way to tell a
        // recipe called Chicken Soup from one that happens to use a stock
        // cube. The answer was in there and so was everything else.
        let scored = filtered.compactMap { recipe -> (Recipe, Int)? in
            let score = Self.relevance(of: recipe, to: terms)
            return score > 0 ? (recipe, score) : nil
        }
        return scored
            .sorted { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                return order(left.0, right.0)
            }
            .map(\.0)
    }

    /// How well a recipe answers the query, or zero if it does not.
    ///
    /// Every term still has to appear somewhere, which is what makes a second
    /// word narrow rather than widen. What changed is that where it appears
    /// decides the order: the title is what the dish is called, a tag is what
    /// somebody filed it under, and an ingredient is a thing it happens to
    /// contain, which is the weakest claim of the three and was previously
    /// worth exactly as much as the first.
    private static func relevance(of recipe: Recipe, to terms: [String]) -> Int {
        let title = tokens(recipe.title)
        let tags = recipe.tags.flatMap(tokens)
        let summary = tokens(recipe.summary)
        let ingredients = recipe.ingredients.flatMap { tokens($0.name) }

        var total = 0
        for term in terms {
            let here: Int
            if title.contains(term) { here = 10 }
            else if title.contains(where: { $0.hasPrefix(term) }) { here = 7 }
            else if tags.contains(where: { $0.hasPrefix(term) }) { here = 4 }
            else if summary.contains(where: { $0.hasPrefix(term) }) { here = 2 }
            else if ingredients.contains(where: { $0.hasPrefix(term) }) { here = 1 }
            else { return 0 }
            total += here
        }
        return total
    }

    /// Words, so a term matches the start of one rather than any run of
    /// letters anywhere. Searching for "pan" used to find "Japanese".
    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
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
