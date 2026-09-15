import Foundation
import SwiftData

/// The hero. Generated from a plan, but able to exist without one so a manual
/// item has somewhere to live before the week is planned. Section 5.3.
@Model
final class GroceryList {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    var mealPlanID: UUID?
    var generatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \GroceryItem.list)
    var items: [GroceryItem]

    init(
        id: UUID = UUID(),
        householdID: UUID,
        mealPlanID: UUID? = nil,
        generatedAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mealPlanID = mealPlanID
        self.generatedAt = generatedAt
        self.items = []
    }

    var orderedItems: [GroceryItem] { items.sorted { $0.position < $1.position } }
}
