import Foundation

/// Merges the records two phones invented separately.
///
/// The week's plan and the grocery list used to take a fresh random id each
/// time a phone created one. Sync merges by id, so the copy your phone made
/// and the copy hers made were simply different records and always would be:
/// each phone pushed its own, received the other's, kept both, and then showed
/// whichever the database happened to hand back first. Both ids are now
/// derived, so two phones compute the same one without talking, but the
/// records already made under the old scheme are still there.
///
/// This leaves one of each, under the id both phones now compute. It runs at
/// launch and is written to be safe to run again: once there is nothing left
/// to merge it does nothing at all, which matters because it will run on every
/// launch for the rest of the app's life.
@MainActor
struct DuplicateReconciler {
    struct Report: Equatable, Sendable {
        var plansMerged = 0
        var mealsMoved = 0
        var listsMerged = 0
        var itemsMoved = 0

        var didNothing: Bool {
            plansMerged == 0 && mealsMoved == 0 && listsMerged == 0 && itemsMoved == 0
        }
    }

    let households: any HouseholdRepository
    let mealPlans: any MealPlanRepository
    let groceryLists: any GroceryListRepository

    @discardableResult
    func run() throws -> Report {
        guard let householdID = try households.all().first?.id else { return Report() }

        var report = Report()
        try mergePlans(householdID: householdID, into: &report)
        try mergeLists(householdID: householdID, into: &report)

        if !report.didNothing {
            try mealPlans.save()
            try groceryLists.save()
        }
        return report
    }

    // MARK: - The week

    private func mergePlans(householdID: UUID, into report: inout Report) throws {
        let byWeek = Dictionary(grouping: try mealPlans.all()) { StableID.day($0.weekStartDate) }

        for (_, plans) in byWeek {
            guard let weekStart = plans.first?.weekStartDate else { continue }
            let canonicalID = StableID.mealPlan(householdID: householdID, weekStartDate: weekStart)
            let strays = plans.filter { $0.id != canonicalID }
            guard !strays.isEmpty else { continue }

            let keeper: MealPlan
            if let found = plans.first(where: { $0.id == canonicalID }) {
                keeper = found
            } else {
                // Nothing here carries the id both phones now compute, so the
                // week has to be made under it and everything moved across.
                // Renaming one in place is not an option: the id is the key
                // the whole sync layer merges on.
                let made = MealPlan(id: canonicalID, householdID: householdID, weekStartDate: weekStart)
                mealPlans.insert(made)
                keeper = made
            }

            for stray in strays {
                for meal in Array(stray.entries) {
                    if !keeper.holds(meal) {
                        let moved = PlannedMeal(
                            householdID: householdID,
                            position: meal.position,
                            date: meal.date,
                            slot: meal.slot,
                            recipeID: meal.recipeID,
                            servings: meal.servings,
                            isCooked: meal.isCooked
                        )
                        moved.plan = keeper
                        keeper.entries.append(moved)
                        report.mealsMoved += 1
                    }
                    // Explicitly, because the cascade would take the row out of
                    // the store here without leaving a tombstone, and the other
                    // phone would put it straight back.
                    mealPlans.deleteEntry(meal)
                }
                stray.entries.removeAll()
                mealPlans.delete(stray)
                report.plansMerged += 1
            }

            keeper.updatedAt = .now
        }
    }

    // MARK: - The list

    private func mergeLists(householdID: UUID, into report: inout Report) throws {
        let canonicalID = StableID.groceryList(householdID: householdID)
        let lists = try groceryLists.all()
        let strays = lists.filter { $0.id != canonicalID }
        guard !strays.isEmpty else { return }

        let keeper: GroceryList
        if let found = lists.first(where: { $0.id == canonicalID }) {
            keeper = found
        } else {
            let made = GroceryList(id: canonicalID, householdID: householdID)
            groceryLists.insert(made)
            keeper = made
        }

        var byID: [UUID: GroceryItem] = [:]
        for row in keeper.items { byID[row.id] = row }
        var position = (keeper.items.map(\.position).max() ?? -1) + 1

        // Oldest first, so the most recently generated list has the last word
        // on anything two copies disagree about.
        for stray in strays.sorted(by: { $0.generatedAt < $1.generatedAt }) {
            for item in Array(stray.items) {
                let id = StableID.groceryItem(
                    listID: canonicalID,
                    canonicalItemID: item.canonicalItemID,
                    displayName: item.displayName
                )

                if let existing = byID[id] {
                    existing.quantities = item.quantities
                    existing.manualQuantities = item.manualQuantities
                    existing.aisle = item.aisle
                    // Ticked on one phone and not the other means somebody
                    // still has to buy it. Getting this wrong sends you home
                    // without the milk, and the other way round only costs a
                    // second look in the trolley.
                    existing.isChecked = existing.isChecked && item.isChecked
                    existing.sourceRecipeIDs = item.sourceRecipeIDs
                    existing.isManual = existing.isManual || item.isManual
                    existing.note = existing.note ?? item.note
                    existing.updatedAt = .now
                } else {
                    let moved = GroceryItem(
                        id: id,
                        householdID: householdID,
                        position: position,
                        canonicalItemID: item.canonicalItemID,
                        displayName: item.displayName,
                        quantities: item.quantities,
                        manualQuantities: item.manualQuantities,
                        aisle: item.aisle,
                        isChecked: item.isChecked,
                        sourceRecipeIDs: item.sourceRecipeIDs,
                        isManual: item.isManual,
                        note: item.note
                    )
                    moved.list = keeper
                    keeper.items.append(moved)
                    byID[id] = moved
                    position += 1
                    report.itemsMoved += 1
                }

                groceryLists.deleteItem(item)
            }
            stray.items.removeAll()
            groceryLists.delete(stray)
            report.listsMerged += 1
        }

        keeper.generatedAt = max(keeper.generatedAt, strays.map(\.generatedAt).max() ?? keeper.generatedAt)
        keeper.updatedAt = .now
    }
}

private extension MealPlan {
    /// Two phones that put the same recipe in the same slot on the same day
    /// planned one meal between them, not two.
    func holds(_ meal: PlannedMeal) -> Bool {
        entries.contains { other in
            other.recipeID == meal.recipeID
                && other.slot == meal.slot
                && other.date.map(StableID.day) == meal.date.map(StableID.day)
        }
    }
}
