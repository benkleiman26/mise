import Foundation

/// Puts the contents of `SeedCatalog` into the store on first launch, and does
/// nothing at all on every launch after that.
///
/// Idempotency comes from `StableID`: every seeded record's id is derived from a
/// stable key, so "have I already added this" is a set membership test rather
/// than a flag someone can forget to set. That matters because this runs on
/// every launch, dozens of times a day in the simulator, and because a device
/// that seeds before it ever syncs must not create a second copy of the table.
///
/// It lives in `App/Seeding` rather than `Domain/Services` because it writes
/// models, and `Domain/Services` is kept free of SwiftData so the list math can
/// move to a package later without untangling anything. See DECISIONS.md.
@MainActor
struct SeedInstaller {
    let households: any HouseholdRepository
    let users: any UserRepository
    let canonicalItems: any CanonicalItemRepository
    let recipes: any RecipeRepository
    let pantry: any PantryRepository

    static let householdName = "My Kitchen"
    static let firstUserName = "You"

    @discardableResult
    func install(_ catalog: SeedCatalog) throws -> SeedReport {
        var report = SeedReport()

        let household = try installHousehold(catalog: catalog, report: &report)
        let itemsByName = try installCanonicalItems(catalog, household: household, report: &report)
        try installRecipes(catalog, household: household, itemsByName: itemsByName, report: &report)
        try installStaplePantryEntries(catalog, household: household, itemsByName: itemsByName, report: &report)

        try households.save()
        return report
    }

    // MARK: - Household

    private func installHousehold(catalog: SeedCatalog, report: inout SeedReport) throws -> Household {
        let householdID = StableID.household()

        if let existing = try households.find(id: householdID) {
            return existing
        }

        // Section 4 names the first household's settings exactly: pescetarian,
        // no restrictions, dislikes olives, 4 servings, US units.
        let household = Household(id: householdID, name: Self.householdName)
        let preferences = HouseholdPreferences(
            id: StableID.preferences(householdID: householdID),
            householdID: householdID,
            menuType: .pescetarian,
            restrictions: [],
            dislikedIngredients: ["olives"],
            defaultServings: 4,
            units: .us,
            aisleOrder: catalog.aisleOrder
        )
        household.preferences = preferences

        households.insert(household)
        report.householdsInserted += 1
        report.preferencesInserted += 1

        // One member, so the household is never memberless and Phase 5 has
        // somewhere to attach an Apple id. There is no sign-in in v1.
        let userID = StableID.user(key: "owner")
        let existingUser = try users.find(id: userID)
        if existingUser == nil {
            let user = User(id: userID, householdID: householdID, displayName: Self.firstUserName)
            users.insert(user)
            household.memberUserIDs = [userID]
            report.usersInserted += 1
        }

        return household
    }

    // MARK: - Canonical items

    private func installCanonicalItems(
        _ catalog: SeedCatalog,
        household: Household,
        report: inout SeedReport
    ) throws -> [String: CanonicalItem] {
        let existing = try canonicalItems.existingIDs()
        var byName: [String: CanonicalItem] = [:]

        for item in try canonicalItems.all() {
            byName[SeedCatalog.key(item.name)] = item
        }

        for seed in catalog.canonicalItems {
            let id = StableID.canonicalItem(name: seed.name)
            if existing.contains(id) { continue }

            let item = CanonicalItem(
                id: id,
                householdID: household.id,
                name: seed.name,
                aliases: seed.aliases,
                aisle: seed.aisle,
                isStaple: seed.isStaple,
                defaultUnit: seed.defaultUnit
            )
            canonicalItems.insert(item)
            byName[SeedCatalog.key(seed.name)] = item
            report.canonicalItemsInserted += 1
        }

        return byName
    }

    // MARK: - Recipes

    private func installRecipes(
        _ catalog: SeedCatalog,
        household: Household,
        itemsByName: [String: CanonicalItem],
        report: inout SeedReport
    ) throws {
        let existing = try recipes.existingIDs()

        for seed in catalog.recipes {
            let recipeID = StableID.recipe(seedID: seed.id)
            if existing.contains(recipeID) { continue }

            let recipe = Recipe(
                id: recipeID,
                householdID: household.id,
                title: seed.title,
                summary: seed.summary,
                sourceType: seed.sourceType,
                prepMinutes: seed.prepMinutes,
                cookMinutes: seed.cookMinutes,
                baseServings: seed.baseServings,
                tags: seed.tags,
                cookware: seed.cookware,
                externalIDs: ["seedID": seed.id]
            )

            // Position is what makes the order survive a round trip through
            // SwiftData, which does not promise one for a relationship.
            var ingredientIDsByKey: [String: UUID] = [:]
            var ingredients: [Ingredient] = []

            for (position, line) in seed.ingredients.enumerated() {
                let ingredientID = StableID.ingredient(recipeSeedID: seed.id, position: position)
                let canonical = catalog.canonicalName(for: line.canonicalKey)
                    .flatMap { itemsByName[SeedCatalog.key($0)] }

                if canonical == nil {
                    // Section 5.1 says this cannot happen in the seed set, and
                    // tools/resource-lint refuses a file where it does. Record
                    // it rather than crashing, so a bad resource is visible in
                    // Settings instead of taking the app down on launch.
                    report.unresolvedIngredients.append("\(seed.id): \(line.canonicalKey)")
                }

                let ingredient = Ingredient(
                    id: ingredientID,
                    householdID: household.id,
                    position: position,
                    name: line.name,
                    canonicalItemID: canonical?.id,
                    quantity: line.quantity,
                    unit: line.unit ?? canonical?.defaultUnit,
                    preparation: line.preparation,
                    isOptional: line.isOptional,
                    aisle: canonical?.aisle ?? .other
                )
                ingredients.append(ingredient)
                ingredientIDsByKey[SeedCatalog.key(line.canonicalKey)] = ingredientID
                report.ingredientsInserted += 1
            }

            var steps: [RecipeStep] = []
            for (position, line) in seed.steps.enumerated() {
                let refs = line.ingredientRefs.compactMap { ingredientIDsByKey[SeedCatalog.key($0)] }
                if refs.count != line.ingredientRefs.count {
                    report.unresolvedStepReferences.append("\(seed.id): step \(position + 1)")
                }

                steps.append(
                    RecipeStep(
                        id: StableID.step(recipeSeedID: seed.id, position: position),
                        householdID: household.id,
                        position: position,
                        text: line.text,
                        timerSeconds: line.timerSeconds,
                        ingredientRefs: refs
                    )
                )
                report.stepsInserted += 1
            }

            recipe.ingredients = ingredients
            recipe.steps = steps
            recipes.insert(recipe)
            report.recipesInserted += 1
        }
    }

    // MARK: - Pantry

    /// Staples default to `have`, which is the whole reason salt and olive oil
    /// stay off the list. Section 1a calls that out as one of Mealime's misses.
    private func installStaplePantryEntries(
        _ catalog: SeedCatalog,
        household: Household,
        itemsByName: [String: CanonicalItem],
        report: inout SeedReport
    ) throws {
        let existing = try pantry.existingIDs()

        for seed in catalog.canonicalItems where seed.isStaple {
            guard let item = itemsByName[SeedCatalog.key(seed.name)] else { continue }
            let entryID = StableID.pantryEntry(householdID: household.id, canonicalItemID: item.id)
            if existing.contains(entryID) { continue }

            pantry.insert(
                PantryEntry(
                    id: entryID,
                    householdID: household.id,
                    canonicalItemID: item.id,
                    status: .have
                )
            )
            report.pantryEntriesInserted += 1
        }
    }
}

/// What a seed run did. Shown in Settings so the phase is verifiable by looking
/// at the app, and asserted on in the tests.
struct SeedReport: Sendable, Equatable {
    var householdsInserted = 0
    var usersInserted = 0
    var preferencesInserted = 0
    var canonicalItemsInserted = 0
    var recipesInserted = 0
    var ingredientsInserted = 0
    var stepsInserted = 0
    var pantryEntriesInserted = 0

    /// Empty in a healthy build. Anything here means a resource file and the
    /// canonical item table disagree.
    var unresolvedIngredients: [String] = []
    var unresolvedStepReferences: [String] = []

    var insertedAnything: Bool {
        householdsInserted > 0
            || usersInserted > 0
            || preferencesInserted > 0
            || canonicalItemsInserted > 0
            || recipesInserted > 0
            || pantryEntriesInserted > 0
    }

    var isClean: Bool {
        unresolvedIngredients.isEmpty && unresolvedStepReferences.isEmpty
    }
}
