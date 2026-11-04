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

    /// Whether this travels between phones.
    ///
    /// The recipe library does not, and that is the decision that makes sync
    /// small enough to trust. 427 recipes with their ingredients and steps is
    /// around eight thousand rows, most of them never changing, and sending
    /// them would dominate every sync for no benefit: both phones can hold the
    /// same library by importing the same files.
    ///
    /// That works because an imported recipe's id is derived from its source
    /// id rather than generated, so the same file produces the same ids on
    /// both devices. A planned meal made here resolves to the right recipe
    /// there without the recipe ever crossing the wire.
    ///
    /// What has to be shared is what changes daily and has to agree: the week,
    /// the list, the pantry, and the household's settings.
    ///
    /// The grocery table is shared too, which the volume argument above never
    /// applied to: it is 395 small rows that almost never change, and the ids
    /// are derived from the names, so both phones already agree about every
    /// item that ships with the app and merging them is a no-op. Leaving it
    /// out had two costs. An item added on one phone never reached the other,
    /// so the pantry entry that pointed at it arrived referring to something
    /// that phone had never heard of and showed nothing at all. And every
    /// spelling taught by categorising an ingredient stayed on the phone that
    /// learned it, so the same tedious work waited on the other one.
    var isShared: Bool {
        switch self {
        case .household, .householdPreferences, .user,
             .canonicalItem, .pantryEntry, .mealPlan, .plannedMeal,
             .groceryList, .groceryItem:
            true
        case .recipe, .ingredient, .recipeStep:
            false
        }
    }

    static var shared: [SyncEntity] { allCases.filter(\.isShared) }
}
