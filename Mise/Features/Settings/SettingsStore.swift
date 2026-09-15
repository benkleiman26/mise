import Foundation

/// Reads the household, its preferences, and how much of the seed is in the
/// store. Phase 0b is read only: editing preferences arrives with section 5.6.
@MainActor
@Observable
final class SettingsStore {
    private let households: any HouseholdRepository
    private let recipes: any RecipeRepository
    private let canonicalItems: any CanonicalItemRepository
    private let pantry: any PantryRepository

    private(set) var household: Household?
    private(set) var recipeCount = 0
    private(set) var canonicalItemCount = 0
    private(set) var pantryCount = 0
    private(set) var loadProblem: String?

    init(
        households: any HouseholdRepository,
        recipes: any RecipeRepository,
        canonicalItems: any CanonicalItemRepository,
        pantry: any PantryRepository
    ) {
        self.households = households
        self.recipes = recipes
        self.canonicalItems = canonicalItems
        self.pantry = pantry
    }

    func load() {
        do {
            household = try households.all().first
            recipeCount = try recipes.count()
            canonicalItemCount = try canonicalItems.count()
            pantryCount = try pantry.count()
            loadProblem = nil
        } catch {
            loadProblem = "Settings could not be read. \(error)"
        }
    }

    var appVersion: String {
        let bundle = MiseBundle.resources
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }
}
