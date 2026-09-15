import Foundation
import SwiftData

/// Everything in Mise belongs to a household. v1 seeds exactly one and shows no
/// sign-in, but section 2 is firm that the model never assumes that, because
/// Phase 5 turns on Supabase row level security keyed on this id.
@Model
final class Household {
    @Attribute(.unique) var id: UUID
    /// Equal to `id` for a household. The field is here so every entity in the
    /// schema carries the same key and a sync layer can treat them alike.
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    var name: String
    var memberUserIDs: [UUID]

    @Relationship(deleteRule: .cascade, inverse: \HouseholdPreferences.household)
    var preferences: HouseholdPreferences?

    init(
        id: UUID = UUID(),
        name: String,
        memberUserIDs: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.memberUserIDs = memberUserIDs
    }
}
