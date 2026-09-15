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
}

extension Recipe: HouseholdRecord {}
extension Ingredient: HouseholdRecord {}
extension RecipeStep: HouseholdRecord {}
extension CanonicalItem: HouseholdRecord {}
extension PantryEntry: HouseholdRecord {}
extension MealPlan: HouseholdRecord {}
extension PlannedMeal: HouseholdRecord {}
extension GroceryList: HouseholdRecord {}
extension GroceryItem: HouseholdRecord {}
extension Household: HouseholdRecord {}
extension User: HouseholdRecord {}
extension HouseholdPreferences: HouseholdRecord {}
