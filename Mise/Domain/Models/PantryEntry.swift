import Foundation
import SwiftData

/// What the household has on hand. No expiration dates and no quantities in v1,
/// per section 5.4.
@Model
final class PantryEntry {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    var canonicalItemID: UUID
    var status: PantryStatus

    init(
        id: UUID = UUID(),
        householdID: UUID,
        canonicalItemID: UUID,
        status: PantryStatus,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.canonicalItemID = canonicalItemID
        self.status = status
    }
}
