import Foundation

/// Turns a week's meals into one grocery list.
///
/// Section 2: "The grocery list is the hero. If anything in the plan cannot be
/// turned into a clean, aisle-grouped, deduplicated list, it is a bug." This is
/// that list, and section 5.3's five rules in order:
///
/// 1. Expand each planned meal's ingredients, scaled by servings over
///    baseServings.
/// 2. Map each ingredient to a canonical item. What does not resolve goes to
///    aisle `other` and is flagged for the user to categorise once.
/// 3. Merge identical items across recipes, summing inside a unit family and
///    keeping both quantities when they cannot be added.
/// 4. Drop what the pantry says we already have. Optional ingredients stay, and
///    are marked.
/// 5. Group by aisle, in the household's store walk order.
///
/// Regenerating preserves two things, per section 4: the check state of items
/// that have not changed, and every manual item.
///
/// Foundation only, so it is testable without a simulator.
struct IngredientInput: Equatable, Sendable {
    /// As written on the recipe, which is what the cook reads.
    let name: String
    let quantity: Double?
    let unit: Unit?
    let isOptional: Bool
    /// Set when the recipe already carries a link, as the seed library does.
    /// When nil the generator resolves the name itself.
    let canonicalItemID: UUID?

    init(name: String, quantity: Double? = nil, unit: Unit? = nil, isOptional: Bool = false, canonicalItemID: UUID? = nil) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.isOptional = isOptional
        self.canonicalItemID = canonicalItemID
    }
}

struct RecipeInput: Equatable, Sendable {
    let id: UUID
    let title: String
    let baseServings: Int
    let ingredients: [IngredientInput]
}

struct PlannedMealInput: Equatable, Sendable {
    let recipe: RecipeInput
    /// Per meal, not per household. Section 1a lists global servings as one of
    /// the things Mealime got wrong.
    let servings: Int

    init(recipe: RecipeInput, servings: Int) {
        self.recipe = recipe
        self.servings = servings
    }
}

struct GroceryDraftItem: Equatable, Sendable {
    var canonicalItemID: UUID?
    var displayName: String
    /// One quantity, or several when they are in different families and section
    /// 4 says to keep both.
    var quantities: [Quantity]
    var aisle: Aisle
    var sourceRecipeIDs: [UUID]
    var isOptional: Bool
    var isManual: Bool
    var isChecked: Bool
    /// The ingredient resolved to nothing, so the user categorises it once and
    /// that teaches the alias table. Section 5.3 rule 2.
    var needsCategorising: Bool
    /// The part of `quantities` the user typed in rather than the plan
    /// producing it. Kept apart so regenerating adds it once instead of
    /// compounding it every time.
    var manualQuantities: [Quantity]

    init(
        canonicalItemID: UUID? = nil,
        displayName: String,
        quantities: [Quantity] = [],
        aisle: Aisle,
        sourceRecipeIDs: [UUID] = [],
        isOptional: Bool = false,
        isManual: Bool = false,
        isChecked: Bool = false,
        needsCategorising: Bool = false,
        manualQuantities: [Quantity] = []
    ) {
        self.canonicalItemID = canonicalItemID
        self.displayName = displayName
        self.quantities = quantities
        self.aisle = aisle
        self.sourceRecipeIDs = sourceRecipeIDs
        self.isOptional = isOptional
        self.isManual = isManual
        self.isChecked = isChecked
        self.needsCategorising = needsCategorising
        self.manualQuantities = manualQuantities
    }

    /// What the shopper reads: "3 lb", or "1/2 bunch + 1/4 cup".
    var formatted: String { UnitConverter.format(quantities) }
}

struct GrocerySection: Equatable, Sendable {
    let aisle: Aisle
    let items: [GroceryDraftItem]
}

struct GeneratedList: Equatable, Sendable {
    let sections: [GrocerySection]

    var items: [GroceryDraftItem] { sections.flatMap(\.items) }
    /// Names that resolved to nothing. The review screen asks about these.
    var needingCategorising: [String] { items.filter(\.needsCategorising).map(\.displayName) }
}

struct ListGenerator {
    let matcher: CanonicalMatcher
    /// Canonical items whose pantry status is `have`. Section 4: the generator
    /// excludes `have` and includes `low` and `out`.
    let pantryHave: Set<UUID>
    /// Canonical items the pantry says are `low` or `out`.
    ///
    /// The other half of section 4's sentence, which was never implemented. The
    /// pantry could only ever take a row away, so a household that tracked its
    /// bread and its tinned tuna watched them run out quietly: nothing adds a
    /// staple to the list, and a staple nobody cooked with this week is exactly
    /// the one about to be missing.
    let pantryRestock: [UUID]
    let aisleOrder: [Aisle]

    init(
        matcher: CanonicalMatcher,
        pantryHave: Set<UUID> = [],
        pantryRestock: [UUID] = [],
        aisleOrder: [Aisle] = Aisle.allCases
    ) {
        self.matcher = matcher
        self.pantryHave = pantryHave
        self.pantryRestock = pantryRestock
        self.aisleOrder = aisleOrder
    }

    /// - Parameter carryingOver: the previous list, so manual items survive and
    ///   unchanged items keep their check mark.
    func generate(plan: [PlannedMealInput], carryingOver previous: [GroceryDraftItem] = []) -> GeneratedList {
        var groups: [GroupKey: Group] = [:]
        var order: [GroupKey] = []

        for meal in plan {
            // Rule 1. A recipe with no base servings would divide by zero, and
            // the honest reading of that is "as written".
            let factor = meal.recipe.baseServings > 0
                ? Double(meal.servings) / Double(meal.recipe.baseServings)
                : 1

            for ingredient in meal.recipe.ingredients {
                // Rule 2.
                let resolved = resolve(ingredient)

                // Rule 4. A staple we already have never reaches the list.
                if let id = resolved.id, pantryHave.contains(id) { continue }

                let key = resolved.key
                if groups[key] == nil {
                    order.append(key)
                    groups[key] = Group(
                        canonicalItemID: resolved.id,
                        displayName: resolved.displayName,
                        aisle: resolved.aisle,
                        needsCategorising: resolved.needsCategorising
                    )
                }
                groups[key]?.add(
                    quantity: Quantity((ingredient.quantity ?? 0) * factor, ingredient.unit),
                    from: meal.recipe.id,
                    isOptional: ingredient.isOptional
                )
            }
        }

        // Rule 4, the half the pantry never got. A tracked item that is low or
        // out joins the list whether or not anything this week asked for it,
        // because the point of tracking something is that it gets replaced
        // before it runs out.
        //
        // It carries no amount. The plan knows it needs 3 tbsp of olive oil;
        // nobody knows how much olive oil a house needs, and a number invented
        // here would be a worse answer than none. The row says buy some.
        for id in pantryRestock {
            let key = GroupKey.canonical(id)
            // `have` wins, as it does in the meal loop above. The two sets are
            // complementary where the store builds them, but this reads them as
            // given and must not contradict rule 4 if they ever overlap.
            guard !pantryHave.contains(id) else { continue }
            // Already on the list because a meal called for it, with a real
            // quantity attached. That row says more than this one would.
            guard groups[key] == nil, let known = matcher.item(id: id) else { continue }
            order.append(key)
            groups[key] = Group(
                canonicalItemID: id,
                displayName: known.name,
                aisle: known.aisle,
                needsCategorising: false
            )
        }

        // Section 4: manual items survive regeneration. When one names
        // something the plan already produced, it merges into that row rather
        // than sitting beside it, which is what a shopper reading the list
        // expects. The hand added amount is folded into the group before the
        // items are built, so the check state comparison below sees the total
        // the user actually saw last time.
        var standaloneManual: [GroceryDraftItem] = []
        for entry in previous where entry.isManual || !entry.manualQuantities.isEmpty {
            let hand = entry.manualQuantities.isEmpty ? entry.quantities : entry.manualQuantities
            let key: GroupKey = entry.canonicalItemID.map(GroupKey.canonical)
                ?? .unresolved(CanonicalMatcher.normalize(entry.displayName))

            if groups[key] != nil {
                groups[key]?.addManual(hand)
            } else {
                var kept = entry
                kept.quantities = hand
                kept.manualQuantities = hand
                kept.isManual = true
                standaloneManual.append(kept)
            }
        }

        // Rule 3.
        var items = order.compactMap { key -> GroceryDraftItem? in
            guard let group = groups[key] else { return nil }
            return group.item(checkedIn: previous)
        }

        items.append(contentsOf: standaloneManual)

        return GeneratedList(sections: sectioned(items))
    }

    // MARK: - Resolving

    private struct Resolution {
        let key: GroupKey
        let id: UUID?
        let displayName: String
        let aisle: Aisle
        let needsCategorising: Bool
    }

    private func resolve(_ ingredient: IngredientInput) -> Resolution {
        // A link the recipe already carries is trusted over re-deriving one,
        // and is looked up by that link rather than by name. Matching the name
        // again would fail on something like "green beans, trimmed", which is
        // how the recipe writes it and not how the table stores it.
        if let id = ingredient.canonicalItemID {
            let known = matcher.item(id: id)
            return Resolution(
                key: .canonical(id),
                id: id,
                displayName: known?.name ?? ingredient.name,
                aisle: known?.aisle ?? .other,
                needsCategorising: known == nil
            )
        }

        let match = matcher.match(ingredient.name)
        guard let item = match.item else {
            // Rule 2: unmatched goes to other, and is flagged once.
            return Resolution(
                key: .unresolved(CanonicalMatcher.normalize(ingredient.name)),
                id: nil,
                displayName: ingredient.name,
                aisle: .other,
                needsCategorising: true
            )
        }
        return Resolution(key: .canonical(item.id), id: item.id, displayName: item.name, aisle: item.aisle, needsCategorising: false)
    }

    // MARK: - Grouping

    private enum GroupKey: Hashable {
        case canonical(UUID)
        case unresolved(String)
    }

    private struct Group {
        let canonicalItemID: UUID?
        let displayName: String
        let aisle: Aisle
        let needsCategorising: Bool

        private var quantities: [Quantity] = []
        /// What the user added by hand to this same line.
        private var manual: [Quantity] = []
        private var sources: [UUID] = []
        /// Only optional if every recipe asking for it says so. One recipe that
        /// needs it makes it needed.
        private var everyUseOptional = true

        init(canonicalItemID: UUID?, displayName: String, aisle: Aisle, needsCategorising: Bool) {
            self.canonicalItemID = canonicalItemID
            self.displayName = displayName
            self.aisle = aisle
            self.needsCategorising = needsCategorising
        }

        mutating func add(quantity: Quantity, from recipeID: UUID, isOptional: Bool) {
            quantities.append(quantity)
            if !sources.contains(recipeID) { sources.append(recipeID) }
            if !isOptional { everyUseOptional = false }
        }

        mutating func addManual(_ hand: [Quantity]) {
            manual.append(contentsOf: hand)
        }

        func item(checkedIn previous: [GroceryDraftItem]) -> GroceryDraftItem {
            let merged = UnitConverter.combine(quantities + manual)
            var item = GroceryDraftItem(
                canonicalItemID: canonicalItemID,
                displayName: displayName,
                quantities: merged,
                aisle: aisle,
                sourceRecipeIDs: sources,
                // Asking for it by hand makes it needed, whatever the recipes
                // say about it being optional.
                isOptional: everyUseOptional && !quantities.isEmpty && manual.isEmpty,
                isManual: false,
                isChecked: false,
                needsCategorising: needsCategorising,
                manualQuantities: UnitConverter.combine(manual)
            )

            // Section 4: regenerating preserves the check state of unchanged
            // items. A changed quantity means there is more to buy, so the tick
            // would be a lie.
            if let before = previous.first(where: { $0.matches(item) }),
               before.formatted == item.formatted {
                item.isChecked = before.isChecked
            }
            return item
        }
    }

    // MARK: - Sections

    /// Rule 5. Aisles the user never reaches are left out entirely rather than
    /// shown empty.
    private func sectioned(_ items: [GroceryDraftItem]) -> [GrocerySection] {
        let order = aisleOrder.isEmpty ? Aisle.allCases : aisleOrder
        let grouped = Dictionary(grouping: items, by: \.aisle)
        return order.compactMap { aisle in
            guard let section = grouped[aisle], !section.isEmpty else { return nil }
            let sorted = section.sorted { left, right in
                // Manual items sit after the ones the plan produced, so the
                // shopper's own additions stay together.
                if left.isManual != right.isManual { return !left.isManual }
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
            return GrocerySection(aisle: aisle, items: sorted)
        }
    }
}

private extension GroceryDraftItem {
    /// Two drafts are the same line if they are the same canonical item, or the
    /// same name when neither resolved.
    func matches(_ other: GroceryDraftItem) -> Bool {
        if let mine = canonicalItemID, let theirs = other.canonicalItemID { return mine == theirs }
        return CanonicalMatcher.normalize(displayName) == CanonicalMatcher.normalize(other.displayName)
    }
}
