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
        let aisle: Aisle
        let items: [GroceryItem]
        var id: String { aisle.rawValue }
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

    var remainingCount: Int {
        sections.flatMap(\.items).filter { !$0.isChecked }.count
    }

    func load() {
        do {
            guard let list = try currentList() else {
                sections = []
                generatedAt = nil
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

            let list = existing ?? GroceryList(householdID: householdID)
            if existing == nil { lists.insert(list) }

            let doomed = list.items
            list.items.removeAll()
            for row in doomed { lists.deleteItem(row) }

            for (index, item) in generated.items.enumerated() {
                let row = GroceryItem(
                    householdID: householdID,
                    position: index,
                    canonicalItemID: item.canonicalItemID,
                    displayName: item.displayName,
                    quantity: item.quantities.first?.quantity,
                    unit: item.quantities.first?.unit,
                    aisle: item.aisle,
                    isChecked: item.isChecked,
                    sourceRecipeIDs: item.sourceRecipeIDs,
                    isManual: item.isManual,
                    // A row can carry two quantities when they cannot be added,
                    // and the model holds one. The written form goes in the note
                    // so nothing is lost. See TODO.md.
                    note: item.quantities.count > 1 ? item.formatted : nil
                )
                row.list = list
                list.items.append(row)
            }
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
                list = GroceryList(householdID: householdID)
                lists.insert(list)
            }

            let parsed = IngredientParser.parse(name)
            let match = try makeMatcher().match(parsed.name)
            let row = GroceryItem(
                householdID: householdID,
                position: (list.items.map(\.position).max() ?? -1) + 1,
                canonicalItemID: match.item?.id,
                displayName: parsed.name.isEmpty ? name : parsed.name,
                quantity: parsed.quantity,
                unit: parsed.unit,
                aisle: match.aisle,
                isManual: true
            )
            row.list = list
            list.items.append(row)
            list.updatedAt = .now
            try lists.save()
            show(list)
        } catch {
            problem = "That item could not be added. \(error)"
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
        let walk = (try? aisleWalk()) ?? Aisle.allCases
        let grouped = Dictionary(grouping: list.orderedItems, by: \.aisle)

        sections = walk.compactMap { aisle in
            guard let items = grouped[aisle], !items.isEmpty else { return nil }
            return Section(aisle: aisle, items: items)
        }
        generatedAt = list.generatedAt
    }

    private func currentList() throws -> GroceryList? {
        try lists.all().sorted { $0.generatedAt > $1.generatedAt }.first
    }

    private func householdID() throws -> UUID {
        guard let household = try households.all().first else { throw ListError.notReady }
        return household.id
    }

    private func makeMatcher() throws -> CanonicalMatcher {
        CanonicalMatcher(items: try canonicalItems.all().map {
            CanonicalCandidate(
                id: $0.id,
                name: $0.name,
                aliases: $0.aliases,
                aisle: $0.aisle,
                isStaple: $0.isStaple,
                defaultUnit: $0.defaultUnit
            )
        })
    }

    private func makeGenerator() throws -> ListGenerator {
        // Section 4: the generator excludes `have` and includes `low` and `out`.
        let have = Set(try pantry.all().filter { $0.status == .have }.map(\.canonicalItemID))
        return ListGenerator(
            matcher: try makeMatcher(),
            pantryHave: have,
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
            quantities: item.quantity.map { [Quantity($0, item.unit)] } ?? [],
            aisle: item.aisle,
            sourceRecipeIDs: item.sourceRecipeIDs,
            isOptional: false,
            isManual: item.isManual,
            isChecked: item.isChecked,
            needsCategorising: item.canonicalItemID == nil && !item.isManual
        )
    }

    enum ListError: LocalizedError {
        case notReady
        var errorDescription: String? {
            "Mise has not finished setting up. Close the app and open it again."
        }
    }
}
