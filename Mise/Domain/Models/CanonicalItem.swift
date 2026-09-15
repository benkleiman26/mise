import Foundation
import SwiftData

/// A grocery item the list generator can merge on. Names and aliases share one
/// namespace, which `tools/resource-lint` enforces, because section 5.3 looks a
/// string up in both and a string claimed twice is ambiguous at exactly the
/// step every merge depends on.
@Model
final class CanonicalItem {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    /// Lowercase and singular, per DECISIONS.md.
    var name: String
    var aliases: [String]
    var aisle: Aisle
    /// Staples default to a pantry status of `have`, which is what keeps salt
    /// and olive oil off every list. Section 1a lists that as one of Mealime's
    /// shortcomings.
    var isStaple: Bool
    var defaultUnit: Unit?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        name: String,
        aliases: [String] = [],
        aisle: Aisle,
        isStaple: Bool = false,
        defaultUnit: Unit? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.aliases = aliases
        self.aisle = aisle
        self.isStaple = isStaple
        self.defaultUnit = defaultUnit
    }
}
