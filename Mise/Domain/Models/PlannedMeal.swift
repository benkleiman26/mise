import Foundation
import SwiftData

/// One meal in a plan. `date` being nil means "this week, no particular day".
@Model
final class PlannedMeal {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    /// Order within the plan, including inside the unscheduled bucket.
    var position: Int

    var date: Date?
    var slot: MealSlot
    var recipeID: UUID
    /// Defaults to the household's `defaultServings` and is editable per meal,
    /// which is one of the things Mealime could not do. Section 1a.
    var servings: Int
    var isCooked: Bool

    var plan: MealPlan?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        position: Int,
        date: Date? = nil,
        slot: MealSlot = .dinner,
        recipeID: UUID,
        servings: Int,
        isCooked: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.position = position
        self.date = date
        self.slot = slot
        self.recipeID = recipeID
        self.servings = servings
        self.isCooked = isCooked
    }
}
