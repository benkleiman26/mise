import Foundation

/// The four fields section 4 puts on every entity, as a protocol, so the shared
/// repository can work on any of them without knowing which it has.
///
/// Declared through extensions rather than on each class so the model files stay
/// readable and the rule is stated once.
protocol HouseholdRecord: AnyObject {
    var id: UUID { get }
    var householdID: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }

    /// Which table this is on the wire. Required rather than optional, so a
    /// model added later cannot quietly become the one thing sync does not
    /// carry.
    static var syncEntity: SyncEntity { get }
}

extension Recipe: HouseholdRecord { static var syncEntity: SyncEntity { .recipe } }
extension Ingredient: HouseholdRecord { static var syncEntity: SyncEntity { .ingredient } }
extension RecipeStep: HouseholdRecord { static var syncEntity: SyncEntity { .recipeStep } }
extension CanonicalItem: HouseholdRecord { static var syncEntity: SyncEntity { .canonicalItem } }
extension PantryEntry: HouseholdRecord { static var syncEntity: SyncEntity { .pantryEntry } }
extension MealPlan: HouseholdRecord { static var syncEntity: SyncEntity { .mealPlan } }
extension PlannedMeal: HouseholdRecord { static var syncEntity: SyncEntity { .plannedMeal } }
extension GroceryList: HouseholdRecord { static var syncEntity: SyncEntity { .groceryList } }
extension GroceryItem: HouseholdRecord { static var syncEntity: SyncEntity { .groceryItem } }
extension Household: HouseholdRecord { static var syncEntity: SyncEntity { .household } }
extension User: HouseholdRecord { static var syncEntity: SyncEntity { .user } }
extension HouseholdPreferences: HouseholdRecord { static var syncEntity: SyncEntity { .householdPreferences } }
