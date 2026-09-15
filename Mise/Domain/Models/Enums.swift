import Foundation

// The enums from spec section 4. Plain Swift on purpose: nothing here imports
// SwiftData or SwiftUI, so the seed decoding in Domain/Services can use them
// and stay portable.

/// Store sections, in the default walk order from section 4. Each household can
/// reorder them, which is why the order lives in HouseholdPreferences and not
/// in this declaration.
enum Aisle: String, Codable, CaseIterable, Sendable {
    case produce
    case meat
    case seafood
    case deliAndCheese
    case dairyAndEggs
    case bakery
    case frozen
    case nutButtersAndJams
    case bakingAndSpices
    case riceGrainsBeans
    case cannedAndJarred
    case pastaAndSauces
    case oilsAndCondiments
    case international
    case snacks
    case beverages
    case household
    case other

    /// The heading shown above a group of grocery items.
    var displayName: String {
        switch self {
        case .produce: "Produce"
        case .meat: "Meat"
        case .seafood: "Seafood"
        case .deliAndCheese: "Deli and Cheese"
        case .dairyAndEggs: "Dairy and Eggs"
        case .bakery: "Bakery"
        case .frozen: "Frozen"
        case .nutButtersAndJams: "Nut Butters, Honey and Jams"
        case .bakingAndSpices: "Baking and Spices"
        case .riceGrainsBeans: "Rice, Grains and Beans"
        case .cannedAndJarred: "Canned and Jarred"
        case .pastaAndSauces: "Pasta and Sauces"
        case .oilsAndCondiments: "Oils, Sauces and Condiments"
        case .international: "International"
        case .snacks: "Snacks"
        case .beverages: "Beverages"
        case .household: "Household"
        case .other: "Other"
        }
    }
}

/// The small, explicit unit set from section 4. Conversions are deliberately
/// not here: UnitConverter lands in Phase 1 and owns that table.
enum Unit: String, Codable, CaseIterable, Sendable {
    case count
    case tsp
    case tbsp
    case cup
    case floz
    case oz
    case lb
    case g
    case kg
    case ml
    case l
    case pinch
    case clove
    case can
    case bunch
    case package
}

/// Allergies and restrictions, matching Mealime's set so an imported profile
/// maps one to one. Section 4.
enum Restriction: String, Codable, CaseIterable, Sendable {
    case shellfish
    case gluten
    case dairy
    case peanut
    case treeNut
    case soy
    case egg
    case sesame
    case mustard
    case sulfite
    case nightshade
}

/// Menu type, again matching Mealime's list. Section 4.
enum MenuType: String, Codable, CaseIterable, Sendable {
    case classic
    case lowCarb
    case keto
    case flexitarian
    case paleo
    case vegetarian
    case pescetarian
    case vegan
}

/// Where a recipe came from. Section 9 notes that only manual and aiGenerated
/// recipes may ever be shared to another household, so this is load bearing
/// rather than decoration.
enum RecipeSourceType: String, Codable, CaseIterable, Sendable {
    case builtIn
    case imported
    case manual
    case aiGenerated
}

/// v1 only surfaces dinner, but the model carries all four so the plan does not
/// have to be reshaped later. Section 4.
enum MealSlot: String, Codable, CaseIterable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
}

/// Section 4: the list generator excludes `have` and includes `low` and `out`.
enum PantryStatus: String, Codable, CaseIterable, Sendable {
    case have
    case low
    case out
}

/// US or metric, per the Units preference in section 1a.
enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case us
    case metric
}
