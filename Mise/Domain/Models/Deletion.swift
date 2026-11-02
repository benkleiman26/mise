import Foundation
import SwiftData

/// A record that something was deleted.
///
/// Sync compares what each device has changed since it last spoke to the
/// server, and a deletion leaves nothing behind to compare. Without this, a
/// meal removed on one phone comes back the next time the other phone pushes
/// its copy, and a grocery item ticked off and deleted reappears in the shop.
/// The absence of a row is not information; a row saying "this is gone" is.
///
/// These are small and they are rubbish after everyone has seen them, so
/// `SyncEngine` clears out old ones once every device has synced past them.
@Model
final class Deletion {
    @Attribute(.unique) var id: UUID
    var householdID: UUID
    var createdAt: Date
    var updatedAt: Date

    /// Which table, as `SyncEntity`'s raw value.
    var entity: String
    /// The id of the record that was deleted.
    var recordID: UUID
    /// Which device did it, so a device can ignore the news of its own delete.
    var deviceID: UUID

    init(
        id: UUID = UUID(),
        householdID: UUID,
        entity: SyncEntity,
        recordID: UUID,
        deviceID: UUID,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.householdID = householdID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entity = entity.rawValue
        self.recordID = recordID
        self.deviceID = deviceID
    }

    var kind: SyncEntity? { SyncEntity(rawValue: entity) }
}

/// Everything sync carries, and the order it has to be applied in.
///
/// Order matters on the way in: a `PlannedMeal` arriving before the `MealPlan`
/// it belongs to has nothing to attach to. The cases are declared parent
/// first and `allCases` is used as the apply order, so adding a table in the
/// wrong place is a visible mistake rather than an intermittent one.
enum SyncEntity: String, Codable, CaseIterable, Sendable {
    case household
    case householdPreferences
    case user
    case canonicalItem
    case recipe
    case ingredient
    case recipeStep
    case pantryEntry
    case mealPlan
    case plannedMeal
    case groceryList
    case groceryItem

    /// Photos are big, they never change once imported, and two phones do not
    /// need the same 600 of them to shop from one list. Section 5.5's sync is
    /// about the plan and the list.
    var carriesPhotos: Bool { false }
}
