import Foundation
import SwiftData

/// The settings from section 1a, kept as their own record so a household can
/// carry them across devices once sync is on.
@Model
final class HouseholdPreferences {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    var menuType: MenuType
    var restrictions: [Restriction]
    var dislikedIngredients: [String]
    var defaultServings: Int
    var units: UnitSystem
    /// Used by "Fill my week" to keep weeknight suggestions quick. Section 5.6.
    var maxWeeknightMinutes: Int
    /// A `Calendar` weekday number. 2 is Monday, which is the default.
    var weekStartsOn: Int
    /// The store walk order the user can rearrange in Settings. Section 5.3.
    var aisleOrder: [Aisle]

    var household: Household?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        menuType: MenuType = .classic,
        restrictions: [Restriction] = [],
        dislikedIngredients: [String] = [],
        defaultServings: Int = 4,
        units: UnitSystem = .us,
        maxWeeknightMinutes: Int = 40,
        weekStartsOn: Int = 2,
        aisleOrder: [Aisle] = Aisle.allCases,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.menuType = menuType
        self.restrictions = restrictions
        self.dislikedIngredients = dislikedIngredients
        self.defaultServings = defaultServings
        self.units = units
        self.maxWeeknightMinutes = maxWeeknightMinutes
        self.weekStartsOn = weekStartsOn
        self.aisleOrder = aisleOrder
    }
}
