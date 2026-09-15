import Foundation
import SwiftData

/// A week of meals. Section 5.2 keeps both ways of planning first class, so a
/// `PlannedMeal` with no date is not a half filled record: it is the Mealime
/// style "just pick four dinners" and has to stay supported.
@Model
final class MealPlan {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    /// The Monday of the week, by default. The household can move the start day.
    var weekStartDate: Date

    @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.plan)
    var entries: [PlannedMeal]

    init(
        id: UUID = UUID(),
        householdID: UUID,
        weekStartDate: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.weekStartDate = weekStartDate
        self.entries = []
    }

    var orderedEntries: [PlannedMeal] { entries.sorted { $0.position < $1.position } }
}
