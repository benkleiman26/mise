import Foundation
import SwiftData

/// A person in a household. `appleUserID` stays empty in v1: sign-in is Phase 5
/// and a local-only household works without an account. Section 3.
@Model
final class User {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    var displayName: String
    var appleUserID: String?

    init(
        id: UUID = UUID(),
        householdID: UUID,
        displayName: String,
        appleUserID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.displayName = displayName
        self.appleUserID = appleUserID
    }
}
