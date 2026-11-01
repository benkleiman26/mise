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
    /// One quantity, or several when they are in different families and
    /// section 4 says to keep both: "1 bunch + 1/4 cup".
    var quantities: [Quantity]
    /// The part of `quantities` the user typed in. Kept apart so regenerating
    /// adds it once rather than compounding it.
    var manualQuantities: [Quantity]
    var aisle: Aisle
    var isChecked: Bool
    var sourceRecipeIDs: [UUID]
    var isManual: Bool
    var note: String?

    var list: GroceryList?

    /// What the shopper reads under the name.
    var formatted: String { UnitConverter.format(quantities) }

    init(
        id: UUID = UUID(),
        householdID: UUID,
        position: Int,
        canonicalItemID: UUID? = nil,
        displayName: String,
        quantities: [Quantity] = [],
        manualQuantities: [Quantity] = [],
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
        self.quantities = quantities
        self.manualQuantities = manualQuantities
        self.aisle = aisle
        self.isChecked = isChecked
        self.sourceRecipeIDs = sourceRecipeIDs
        self.isManual = isManual
        self.note = note
    }
}
