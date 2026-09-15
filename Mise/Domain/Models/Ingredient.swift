import Foundation
import SwiftData

/// One line item inside a recipe. `name` is kept as written, because "boneless
/// skinless chicken thighs" is what the cook needs to read, while
/// `canonicalItemID` is what the grocery list merges on. Section 4.
@Model
final class Ingredient {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    /// Recipe order. See `Recipe.orderedIngredients`.
    var position: Int

    var name: String
    var canonicalItemID: UUID?
    var quantity: Double?
    var unit: Unit?
    var preparation: String?
    var isOptional: Bool
    /// Inherited from the canonical item when linked, and `other` when not, so
    /// an unresolved line still lands somewhere on the list. Section 5.3.
    var aisle: Aisle

    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        position: Int,
        name: String,
        canonicalItemID: UUID? = nil,
        quantity: Double? = nil,
        unit: Unit? = nil,
        preparation: String? = nil,
        isOptional: Bool = false,
        aisle: Aisle = .other,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.position = position
        self.name = name
        self.canonicalItemID = canonicalItemID
        self.quantity = quantity
        self.unit = unit
        self.preparation = preparation
        self.isOptional = isOptional
        self.aisle = aisle
    }
}
