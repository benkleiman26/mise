import Foundation

/// The week's meals. Section 5.2 keeps two ways of planning first class; this
/// is the Mealime one, a handful of dinners with no particular day, which
/// section 1a says has to stay supported.
@MainActor
@Observable
final class PlanStore {
    /// A planned meal paired with the recipe it points at, so the view does not
    /// have to go looking.
    struct Entry: Identifiable {
        let meal: PlannedMeal
        let recipe: Recipe
        var id: UUID { meal.id }
    }

    private let plans: any MealPlanRepository
    private let recipes: any RecipeRepository
    private let households: any HouseholdRepository

    private(set) var entries: [Entry] = []
    private(set) var problem: String?

    init(plans: any MealPlanRepository, recipes: any RecipeRepository, households: any HouseholdRepository) {
        self.plans = plans
        self.recipes = recipes
        self.households = households
    }

    var isEmpty: Bool { entries.isEmpty }

    /// The Monday of the current week, which is section 4's default start day.
    static var currentWeekStart: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        return calendar.date(from: components) ?? Calendar.current.startOfDay(for: .now)
    }

    func load() {
        do {
            let plan = try currentPlan()
            let library = try recipes.all()
            let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            entries = plan.orderedEntries.compactMap { meal in
                byID[meal.recipeID].map { Entry(meal: meal, recipe: $0) }
            }
            problem = nil
        } catch {
            entries = []
            problem = "This week's plan could not be read. \(error)"
        }
    }

    /// `servings` is what the cook asked for on the recipe screen. Without one
    /// the household default is used, which is what the plus button on the
    /// library row means.
    func add(_ recipe: Recipe, servings: Int? = nil) {
        do {
            let plan = try currentPlan()
            // Adding the same dinner twice is a real thing people do, so this
            // does not dedupe.
            let meal = PlannedMeal(
                householdID: plan.householdID,
                position: (plan.entries.map(\.position).max() ?? -1) + 1,
                recipeID: recipe.id,
                servings: servings ?? (try defaultServings())
            )
            meal.plan = plan
            plan.entries.append(meal)
            plan.updatedAt = .now
            try plans.save()
            load()
        } catch {
            problem = "That meal could not be added. \(error)"
        }
    }

    func remove(_ entry: Entry) {
        do {
            let plan = entry.meal.plan
            plan?.entries.removeAll { $0.id == entry.meal.id }
            plans.deleteEntry(entry.meal)
            plan?.updatedAt = .now
            try plans.save()
            load()
        } catch {
            problem = "That meal could not be removed. \(error)"
        }
    }

    /// Per meal, not per household. Section 1a lists global servings as one of
    /// the things Mealime got wrong.
    func setServings(_ servings: Int, for entry: Entry) {
        guard servings > 0 else { return }
        do {
            entry.meal.servings = servings
            entry.meal.updatedAt = .now
            try plans.save()
            load()
        } catch {
            problem = "The serving count could not be saved. \(error)"
        }
    }

    func clear() {
        do {
            let plan = try currentPlan()
            let doomed = plan.entries
            plan.entries.removeAll()
            for meal in doomed { plans.deleteEntry(meal) }
            plan.updatedAt = .now
            try plans.save()
            load()
        } catch {
            problem = "The plan could not be cleared. \(error)"
        }
    }

    // MARK: - Private

    /// This week's plan, created on first use. One plan at a time, as section
    /// 1a describes.
    private func currentPlan() throws -> MealPlan {
        let weekStart = Self.currentWeekStart
        if let existing = try plans.all().first(where: { Calendar.current.isDate($0.weekStartDate, inSameDayAs: weekStart) }) {
            return existing
        }
        let plan = MealPlan(householdID: try householdID(), weekStartDate: weekStart)
        plans.insert(plan)
        try plans.save()
        return plan
    }

    private func householdID() throws -> UUID {
        guard let household = try households.all().first else {
            throw PlanError.noHousehold
        }
        return household.id
    }

    private func defaultServings() throws -> Int {
        (try households.all().first?.preferences?.defaultServings) ?? 4
    }

    enum PlanError: LocalizedError {
        case noHousehold
        var errorDescription: String? {
            "Mise has not finished setting up. Close the app and open it again."
        }
    }
}
