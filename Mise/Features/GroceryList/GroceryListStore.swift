import Foundation

/// The hero screen's store. Builds `ListGenerator`'s inputs out of what is in
/// the store, runs it, and writes the result back as `GroceryItem` rows.
///
/// Section 5.3 rule by rule happens inside `ListGenerator`, which is tested
/// against the real seed library. This file is only the wiring.
@MainActor
@Observable
final class GroceryListStore {
    struct Section: Identifiable {
        enum Kind: Equatable {
            /// Standing order: the pantry says these are low or out, whether or
            /// not anything this week asked for them.
            case runningLow
            case aisle(Aisle)
        }

        let kind: Kind
        let title: String
        let items: [GroceryItem]
        var id: String {
            switch kind {
            case .runningLow: "running-low"
            case .aisle(let aisle): aisle.rawValue
            }
        }
    }

    private let lists: any GroceryListRepository
    private let plans: any MealPlanRepository
    private let recipes: any RecipeRepository
    private let canonicalItems: any CanonicalItemRepository
    private let pantry: any PantryRepository
    private let households: any HouseholdRepository

    private(set) var sections: [Section] = []
    private(set) var generatedAt: Date?
    private(set) var problem: String?

    /// A shopping list should get shorter as you shop. Ticked rows leave the
    /// list rather than sitting there struck through, because the thing a
    /// shopper wants to see is what is left.
    var showsCompleted = false {
        didSet { if showsCompleted != oldValue { load() } }
    }

    /// Counted off the whole list rather than off what is on screen, which is
    /// the point: hiding the ticked ones must not change what the footer says
    /// is left.
    private(set) var remainingCount = 0
    private(set) var completedCount = 0
    /// Whether there is a list at all, as opposed to one with nothing left on
    /// it. An empty screen means two very different things.
    private(set) var hasList = false

    /// What this week's meals need that the pantry says is already in.
    ///
    /// Rule 4 keeps these off the shopping list, which is right: nobody wants
    /// to buy salt every week. But dropping them silently means a recipe can
    /// call for eight things and the list show three, with no way to tell
    /// whether the other five were covered or lost. So they are said, by name,
    /// at the bottom, where they answer the question without joining the shop.
    private(set) var inThePantry: [String] = []

    init(
        lists: any GroceryListRepository,
        plans: any MealPlanRepository,
        recipes: any RecipeRepository,
        canonicalItems: any CanonicalItemRepository,
        pantry: any PantryRepository,
        households: any HouseholdRepository
    ) {
        self.lists = lists
        self.plans = plans
        self.recipes = recipes
        self.canonicalItems = canonicalItems
        self.pantry = pantry
        self.households = households
    }

    var isEmpty: Bool { sections.isEmpty }

    /// The meals a row came from, by title. Section 5.3: tap an item and see
    /// which meals need it, which is how a shopper decides whether to skip it.
    func meals(for item: GroceryItem) -> [String] {
        guard !item.sourceRecipeIDs.isEmpty else { return [] }
        let wanted = Set(item.sourceRecipeIDs)
        let titles = (try? recipes.all())?
            .filter { wanted.contains($0.id) }
            .map(\.title) ?? []
        return titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func load() {
        do {
            guard let list = try currentList() else {
                sections = []
                generatedAt = nil
                hasList = false
                remainingCount = 0
                completedCount = 0
                return
            }
            show(list)
            problem = nil
        } catch {
            sections = []
            problem = "The grocery list could not be read. \(error)"
        }
    }

    /// Section 4: regenerating preserves the check state of unchanged items and
    /// every manual item. `ListGenerator` does that; this hands it the old list.
    func regenerate() {
        do {
            let householdID = try self.householdID()
            let existing = try currentList()
            let previous = existing?.orderedItems.map { draft($0) } ?? []

            let generated = try makeGenerator().generate(plan: try planInputs(), carryingOver: previous)

            let list = existing ?? GroceryList(
                id: StableID.groceryList(householdID: householdID),
                householdID: householdID
            )
            if existing == nil { lists.insert(list) }

            // Updated in place, keyed by what each line is rather than by when
            // it was made.
            //
            // Clearing the list and building it again was simpler and wrong in
            // two ways once a second phone exists. It wrote a tombstone per
            // row, and a tombstone is a decision: the other phone reads it as
            // "this was taken off the list" and removes its own copy. And the
            // replacement rows carried new random ids, so both phones ended up
            // with their own "2 lemons" and the list showed everything twice.
            var byID: [UUID: GroceryItem] = [:]
            for row in list.items { byID[row.id] = row }

            var kept: Set<UUID> = []
            for (index, item) in generated.items.enumerated() {
                // Two lines that key the same would collide. The generator
                // merges on the canonical item so this should not happen, but
                // the tie-break has to be deterministic rather than lucky:
                // both phones must land on the same answer.
                var tieBreak = 0
                var id = StableID.groceryItem(
                    listID: list.id,
                    canonicalItemID: item.canonicalItemID,
                    displayName: item.displayName
                )
                while kept.contains(id) {
                    tieBreak += 1
                    id = StableID.groceryItem(
                        listID: list.id,
                        canonicalItemID: item.canonicalItemID,
                        displayName: item.displayName,
                        tieBreak: tieBreak
                    )
                }
                kept.insert(id)

                if let row = byID[id] {
                    row.position = index
                    row.canonicalItemID = item.canonicalItemID
                    row.displayName = item.displayName
                    row.quantities = item.quantities
                    row.manualQuantities = item.manualQuantities
                    row.aisle = item.aisle
                    row.isChecked = item.isChecked
                    row.sourceRecipeIDs = item.sourceRecipeIDs
                    row.isManual = item.isManual
                    row.updatedAt = .now
                } else {
                    let row = GroceryItem(
                        id: id,
                        householdID: householdID,
                        position: index,
                        canonicalItemID: item.canonicalItemID,
                        displayName: item.displayName,
                        quantities: item.quantities,
                        manualQuantities: item.manualQuantities,
                        aisle: item.aisle,
                        isChecked: item.isChecked,
                        sourceRecipeIDs: item.sourceRecipeIDs,
                        isManual: item.isManual
                    )
                    row.list = list
                    list.items.append(row)
                }
            }

            let gone = list.items.filter { !kept.contains($0.id) }
            list.items.removeAll { !kept.contains($0.id) }
            for row in gone { lists.deleteItem(row) }
            list.generatedAt = .now
            list.updatedAt = .now
            try lists.save()

            show(list)
            problem = nil
        } catch {
            problem = "The list could not be made. \(error)"
        }
    }

    func toggle(_ item: GroceryItem) {
        do {
            item.isChecked.toggle()
            item.updatedAt = .now
            try lists.save()
            load()
        } catch {
            problem = "That could not be saved. \(error)"
        }
    }

    /// Section 5.3: a manual item survives regeneration, which is how the dish
    /// soap stays on the list.
    func addManual(_ text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let householdID = try self.householdID()
            let list: GroceryList
            if let existing = try currentList() {
                list = existing
            } else {
                list = GroceryList(
                    id: StableID.groceryList(householdID: householdID),
                    householdID: householdID
                )
                lists.insert(list)
            }

            let parsed = IngredientParser.parse(name)
            let match = try makeMatcher().match(parsed.name)
            let display = parsed.name.isEmpty ? name : parsed.name
            let hand = parsed.quantity.map { [Quantity($0, parsed.unit)] } ?? []

            // Asked for on 2026-11-01: typing something already on the list
            // adds to that row rather than making a second one. The hand added
            // part is recorded separately so the next regeneration adds it
            // once instead of compounding it.
            if let existing = row(in: list, matching: match.item?.id, named: display) {
                existing.quantities = UnitConverter.combine(existing.quantities + hand)
                existing.manualQuantities = UnitConverter.combine(existing.manualQuantities + hand)
                // There is more to buy than when it was ticked.
                existing.isChecked = false
                existing.updatedAt = .now
            } else {
                // The same key the generator uses, so that regenerating
                // updates this row rather than deleting it and making a new
                // one, and so that both phones adding "paper towels" by hand
                // end up with one line instead of two.
                let row = GroceryItem(
                    id: StableID.groceryItem(
                        listID: list.id,
                        canonicalItemID: match.item?.id,
                        displayName: display
                    ),
                    householdID: householdID,
                    position: (list.items.map(\.position).max() ?? -1) + 1,
                    canonicalItemID: match.item?.id,
                    displayName: display,
                    quantities: hand,
                    manualQuantities: hand,
                    aisle: match.aisle,
                    isManual: true
                )
                row.list = list
                list.items.append(row)
            }
            list.updatedAt = .now
            try lists.save()
            show(list)
        } catch {
            problem = "That item could not be added. \(error)"
        }
    }

    /// Applies what the detail sheet was edited to, in one write.
    ///
    /// One write rather than one per field, because every write stamps
    /// `updatedAt` and becomes a record the other phone has to take, and a
    /// person correcting a name types twelve times to mean one change.
    func update(_ item: GroceryItem, name: String, amount: String, aisle: Aisle) {
        do {
            let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let typed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            var changed = false

            if !newName.isEmpty, newName != item.displayName {
                item.displayName = newName
                changed = true
            }

            let amounts: [Quantity]
            if typed.isEmpty {
                amounts = []
            } else {
                let parsed = IngredientParser.parse(typed)
                amounts = parsed.quantity.map { UnitConverter.combine([Quantity($0, parsed.unit)]) } ?? []
            }
            if amounts != item.quantities {
                // Both, because a person who has typed over the amount means
                // the list to say that, and the manual half is what survives
                // the next regeneration.
                item.quantities = amounts
                item.manualQuantities = amounts
                changed = true
            }

            if aisle != item.aisle {
                item.aisle = aisle
                // An item the grocery table knows moves the table with it.
                // Putting acai in Produce once should put it there next week
                // and on the other phone, not just on this line of this list.
                if let canonicalID = item.canonicalItemID,
                   let canonical = try canonicalItems.find(id: canonicalID) {
                    canonical.aisle = aisle
                    canonical.updatedAt = .now
                }
                changed = true
            }

            guard changed else { return }
            item.updatedAt = .now
            try lists.save()
            load()
        } catch {
            problem = "That could not be saved. \(error)"
        }
    }

    func delete(_ item: GroceryItem) {
        do {
            item.list?.items.removeAll { $0.id == item.id }
            lists.deleteItem(item)
            try lists.save()
            load()
        } catch {
            problem = "That item could not be removed. \(error)"
        }
    }

    // MARK: - Private

    private func show(_ list: GroceryList) {
        let all = list.orderedItems
        hasList = true
        remainingCount = all.filter { !$0.isChecked }.count
        completedCount = all.count - remainingCount

        let shown = showsCompleted ? all : all.filter { !$0.isChecked }
        let walk = (try? aisleWalk()) ?? Aisle.allCases

        // The standing order, separated and first.
        //
        // A restock row and a row a meal asked for look identical, and they
        // answer different questions: one is "we are out of bread", the other
        // is "Thursday needs bread". Mixed together, two dinners produce a
        // list of forty lines and no way to tell which is which.
        //
        // Told apart by what the generator gave them rather than by a flag on
        // the row: a restock line is the only kind that carries no quantity
        // and names no recipe, because nobody knows how much olive oil a house
        // needs and nothing this week asked for it.
        let isRestock = { (item: GroceryItem) in
            !item.isManual && item.sourceRecipeIDs.isEmpty && item.quantities.isEmpty
        }
        let low = shown.filter(isRestock)
        let rest = shown.filter { !isRestock($0) }
        let grouped = Dictionary(grouping: rest, by: \.aisle)

        var built: [Section] = []
        if !low.isEmpty {
            built.append(Section(
                kind: .runningLow,
                title: "Running low",
                items: low.sorted { walkOrder($0.aisle, before: $1.aisle, in: walk) }
            ))
        }
        built.append(contentsOf: walk.compactMap { aisle in
            guard let items = grouped[aisle], !items.isEmpty else { return nil }
            return Section(kind: .aisle(aisle), title: aisle.displayName, items: items)
        })
        sections = built

        inThePantry = pantryLines()
        generatedAt = list.generatedAt
    }

    /// Keeps the standing order in store-walk order inside its own section, so
    /// it still reads like a route rather than an alphabet.
    private func walkOrder(_ left: Aisle, before right: Aisle, in walk: [Aisle]) -> Bool {
        let a = walk.firstIndex(of: left) ?? walk.count
        let b = walk.firstIndex(of: right) ?? walk.count
        if a != b { return a < b }
        return left.rawValue < right.rawValue
    }

    /// The planned ingredients rule 4 took out, by name.
    private func pantryLines() -> [String] {
        guard let plan = try? planInputs(), !plan.isEmpty else { return [] }
        guard let have = try? pantry.all().filter({ $0.status == .have }) else { return [] }
        let haveIDs = Set(have.map(\.canonicalItemID))
        guard !haveIDs.isEmpty else { return [] }

        let matcher = (try? makeMatcher()) ?? CanonicalMatcher(items: [])
        var names: Set<String> = []
        for meal in plan {
            for ingredient in meal.recipe.ingredients {
                let id = ingredient.canonicalItemID ?? matcher.match(ingredient.name).item?.id
                guard let id, haveIDs.contains(id) else { continue }
                names.insert(matcher.item(id: id)?.name ?? ingredient.name)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The row a hand typed item belongs on, by canonical item when both have
    /// one and by normalized name otherwise. Same test `ListGenerator` uses, so
    /// adding by hand and regenerating agree about what counts as one line.
    private func row(in list: GroceryList, matching id: UUID?, named name: String) -> GroceryItem? {
        list.items.first { row in
            if let mine = id, let theirs = row.canonicalItemID { return mine == theirs }
            return CanonicalMatcher.normalize(row.displayName) == CanonicalMatcher.normalize(name)
        }
    }

    private func currentList() throws -> GroceryList? {
        try lists.all().sorted { $0.generatedAt > $1.generatedAt }.first
    }

    private func householdID() throws -> UUID {
        guard let household = try households.all().first else { throw ListError.notReady }
        return household.id
    }

    private func makeMatcher() throws -> CanonicalMatcher {
        CanonicalMatcher(items: try canonicalItems.all().map(CanonicalCandidate.init))
    }

    private func makeGenerator() throws -> ListGenerator {
        // Section 4: the generator excludes `have` and includes `low` and `out`.
        // Both halves, read from one fetch so the two cannot disagree.
        let entries = try pantry.all()
        let have = Set(entries.filter { $0.status == .have }.map(\.canonicalItemID))
        let restock = entries.filter { $0.status != .have }.map(\.canonicalItemID)
        return ListGenerator(
            matcher: try makeMatcher(),
            pantryHave: have,
            pantryRestock: restock,
            aisleOrder: try aisleWalk()
        )
    }

    /// Section 5.3: the store walk order the household set in Settings, or the
    /// built in order when they have not touched it.
    private func aisleWalk() throws -> [Aisle] {
        let saved = try households.all().first?.preferences?.aisleOrder ?? []
        return saved.isEmpty ? Aisle.allCases : saved
    }

    private func planInputs() throws -> [PlannedMealInput] {
        let weekStart = PlanStore.currentWeekStart
        guard let plan = try plans.all().first(where: { Calendar.current.isDate($0.weekStartDate, inSameDayAs: weekStart) }) else {
            return []
        }
        let byID = Dictionary(try recipes.all().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return plan.orderedEntries.compactMap { meal in
            guard let recipe = byID[meal.recipeID] else { return nil }
            return PlannedMealInput(recipe: input(for: recipe), servings: meal.servings)
        }
    }

    private func input(for recipe: Recipe) -> RecipeInput {
        RecipeInput(
            id: recipe.id,
            title: recipe.title,
            baseServings: recipe.baseServings,
            ingredients: recipe.orderedIngredients.map {
                IngredientInput(
                    name: $0.name,
                    quantity: $0.quantity,
                    unit: $0.unit,
                    isOptional: $0.isOptional,
                    canonicalItemID: $0.canonicalItemID
                )
            }
        )
    }

    private func draft(_ item: GroceryItem) -> GroceryDraftItem {
        GroceryDraftItem(
            canonicalItemID: item.canonicalItemID,
            displayName: item.displayName,
            quantities: item.quantities,
            aisle: item.aisle,
            sourceRecipeIDs: item.sourceRecipeIDs,
            isOptional: false,
            isManual: item.isManual,
            isChecked: item.isChecked,
            needsCategorising: item.canonicalItemID == nil && !item.isManual,
            manualQuantities: item.manualQuantities
        )
    }

    enum ListError: LocalizedError {
        case notReady
        var errorDescription: String? {
            "Mise has not finished setting up. Close the app and open it again."
        }
    }
}
