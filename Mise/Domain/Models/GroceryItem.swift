import Foundation
import SwiftData

/// One row on the list. `sourceRecipeIDs` is what lets a shopper tap an item and
/// see which meals need it, and `isManual` is what keeps the dish soap on the
/// list through a regeneration. Section 5.3.
@Model
final class GroceryItem {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    var position: Int

    var canonicalItemID: UUID?
    var displayName: String
    var quantity: Double?
    var unit: Unit?
    var aisle: Aisle
    var isChecked: Bool
    var sourceRecipeIDs: [UUID]
    var isManual: Bool
    var note: String?

    var list: GroceryList?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        position: Int,
        canonicalItemID: UUID? = nil,
        displayName: String,
        quantity: Double? = nil,
        unit: Unit? = nil,
        aisle: Aisle = .other,
        isChecked: Bool = false,
        sourceRecipeIDs: [UUID] = [],
        isManual: Bool = false,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.position = position
        self.canonicalItemID = canonicalItemID
        self.displayName = displayName
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
        self.isChecked = isChecked
        self.sourceRecipeIDs = sourceRecipeIDs
        self.isManual = isManual
        self.note = note
    }
}
