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
    ///
    /// Not called `entity`, which is the obvious name and a trap. SwiftData is
    /// built on Core Data, every model is an `NSManagedObject` underneath, and
    /// `NSManagedObject` already has an `entity` property returning an
    /// `NSEntityDescription`. The names collide, and the collision does not
    /// show up at build time: it crashes inside the save with "Could not cast
    /// value of type NSEntityDescription to NSString", from a stack frame that
    /// names neither this property nor this model. Every delete in the app
    /// writes one of these, so it took everything down with it.
    /// The default is what lets the store migrate itself.
    ///
    /// Renaming a property is a schema change, and SwiftData migrates in place
    /// without being asked only when it can fill the new column on its own. A
    /// mandatory attribute with no default gives it nothing to write, so the
    /// store refuses to open, the container falls back to memory, and the app
    /// launches looking like somebody deleted every recipe.
    var recordEntity: String = ""
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
        self.recordEntity = entity.rawValue
        self.recordID = recordID
        self.deviceID = deviceID
    }

    var kind: SyncEntity? { SyncEntity(rawValue: recordEntity) }
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

    /// Whether this travels between phones. Everything does.
    ///
    /// The recipe library was held back at first, on the grounds that 427
    /// recipes with their ingredients and steps is around eight thousand rows
    /// and both phones could hold the same library by importing the same
    /// files. That is true, and it is not enough. It only covers the recipes
    /// that came from a file. A recipe imported from a link, or written down,
    /// exists on one phone, and the other phone's week can hold a meal
    /// pointing at a recipe it has never heard of.
    ///
    /// The eight thousand rows are a one-off. They go up once, almost none of
    /// them ever change, and the sequence cursor means a device picks up where
    /// it left off rather than starting again. What does not go is the
    /// photographs: see the encoder.
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
             .canonicalItem, .recipe, .ingredient, .recipeStep,
             .pantryEntry, .mealPlan, .plannedMeal,
             .groceryList, .groceryItem:
            true
        }
    }

    static var shared: [SyncEntity] { allCases.filter(\.isShared) }
}
