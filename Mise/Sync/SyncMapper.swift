import Foundation

/// Turns the stored models into wire records and back.
///
/// Written out per entity rather than through reflection. Reflection would be
/// shorter and would silently start carrying any field added later, including
/// ones that should never leave the device. Eight explicit encoders is more
/// lines and no surprises.
///
/// Decoding is tolerant on purpose: a field the reader does not understand is
/// left alone rather than refused, because the two phones in a household will
/// not be running the same version of the app.
@MainActor
struct SyncMapper {
    let households: any HouseholdRepository
    let users: any UserRepository
    let canonicalItems: any CanonicalItemRepository
    let recipes: any RecipeRepository
    let pantry: any PantryRepository
    let plans: any MealPlanRepository
    let lists: any GroceryListRepository

    // MARK: - Out

    /// What this device holds, for the tables that should not drift.
    ///
    /// The library only: recipes with their ingredients and steps, the grocery
    /// table and the pantry. Those change rarely, so this device holding more
    /// than the server does means something was refused rather than something
    /// being in flight. The week and the list are left out on purpose: they
    /// change constantly and a difference between two phones mid-shop is
    /// ordinary rather than a fault.
    func libraryCounts() throws -> [String: Int] {
        [
            SyncEntity.canonicalItem.rawValue: try canonicalItems.count(),
            SyncEntity.recipe.rawValue: try recipes.count(),
            SyncEntity.ingredient.rawValue: try recipes.allIngredients().count,
            SyncEntity.recipeStep.rawValue: try recipes.allSteps().count,
            SyncEntity.pantryEntry.rawValue: try pantry.count(),
        ]
    }

    func records(changedSince cursor: Date?) throws -> [SyncRecord] {
        var out: [SyncRecord] = []
        let after = cursor ?? .distantPast

        for household in try households.all() {
            if household.updatedAt > after { out.append(encode(household)) }
            // Not nested inside the household's own test. Changing the store
            // walk order or the default servings touches the preferences and
            // nothing else, and nesting meant those changes waited for some
            // unrelated edit to the household before they could travel.
            if let preferences = household.preferences, preferences.updatedAt > after {
                out.append(encode(preferences))
            }
        }
        for user in try users.all() where user.updatedAt > after {
            out.append(encode(user))
        }
        // Asked of the store, not filtered afterwards.
        //
        // These two tables are the whole library. Reading all of it to find
        // what changed cost about ten seconds of a phone that would not answer
        // a touch, every thirty seconds, on both phones, for ever: the walk is
        // the same size whether anything changed or not. A fetch with a
        // predicate normally returns nothing and costs nothing.
        for item in try canonicalItems.changed(since: after) {
            out.append(encode(item))
        }
        for recipe in try recipes.changed(since: after) {
            out.append(encode(recipe))
        }
        for ingredient in try recipes.changedIngredients(since: after) {
            // Without a recipe it is a stray, and sending it would describe a
            // child of nothing.
            guard let recipe = ingredient.recipe else { continue }
            out.append(encode(ingredient, in: recipe))
        }
        for step in try recipes.changedSteps(since: after) {
            guard let recipe = step.recipe else { continue }
            out.append(encode(step, in: recipe))
        }
        for entry in try pantry.all() where entry.updatedAt > after {
            out.append(encode(entry))
        }
        for plan in try plans.all() {
            if plan.updatedAt > after { out.append(encode(plan)) }
            for meal in plan.entries where meal.updatedAt > after { out.append(encode(meal)) }
        }
        for list in try lists.all() {
            if list.updatedAt > after { out.append(encode(list)) }
            for item in list.items where item.updatedAt > after { out.append(encode(item)) }
        }
        return out
    }

    /// `householdID` here is the record's own, which the client replaces with
    /// the sharing group's id on the wire. The two are different and keeping
    /// them apart is what the first real sync got wrong.
    private func record(_ entity: SyncEntity, _ model: any HouseholdRecord, _ fields: [String: SyncValue]) -> SyncRecord {
        var all = fields
        all["createdAt"] = .date(model.createdAt)
        return SyncRecord(
            entity: entity,
            id: model.id,
            householdID: model.householdID,
            updatedAt: model.updatedAt,
            fields: all
        )
    }

    private func encode(_ household: Household) -> SyncRecord {
        record(.household, household, ["name": .string(household.name)])
    }

    private func encode(_ preferences: HouseholdPreferences) -> SyncRecord {
        record(.householdPreferences, preferences, [
            "menuType": .string(preferences.menuType.rawValue),
            "restrictions": .strings(preferences.restrictions.map(\.rawValue)),
            "dislikedIngredients": .strings(preferences.dislikedIngredients),
            "defaultServings": .integer(preferences.defaultServings),
            "units": .string(preferences.units.rawValue),
            "maxWeeknightMinutes": .integer(preferences.maxWeeknightMinutes),
            "weekStartsOn": .integer(preferences.weekStartsOn),
            "aisleOrder": .strings(preferences.aisleOrder.map(\.rawValue)),
        ])
    }

    /// The name only. `appleUserID` identifies a person to Apple, it is not
    /// needed to show who ticked something off, and the less of it that
    /// travels the better.
    private func encode(_ user: User) -> SyncRecord {
        record(.user, user, ["displayName": .string(user.displayName)])
    }

    /// `learnedAliases` travels, `aliases` does not need to: the shipped ones
    /// come from the bundle and both phones have the same bundle sooner or
    /// later. They are sent anyway, because an item added by hand has none and
    /// the field has to mean the same thing on both sides of the wire.
    private func encode(_ item: CanonicalItem) -> SyncRecord {
        var fields: [String: SyncValue] = [
            "name": .string(item.name),
            "aliases": .strings(item.aliases),
            "learnedAliases": .strings(item.learnedAliases),
            "aisle": .string(item.aisle.rawValue),
            "isStaple": .boolean(item.isStaple),
        ]
        if let unit = item.defaultUnit { fields["defaultUnit"] = .string(unit.rawValue) }
        return record(.canonicalItem, item, fields)
    }

    /// Everything but the picture.
    ///
    /// `imageData` is the one field deliberately left behind. 427 recipes'
    /// photos is most of a free database allowance spent on bytes both phones
    /// already have from the same import, and a grocery list that cannot sync
    /// because the recipe pictures filled the disk is a bad trade. `imageURL`
    /// travels, so a recipe imported from a link can fetch its own picture.
    private func encode(_ recipe: Recipe) -> SyncRecord {
        var fields: [String: SyncValue] = [
            "title": .string(recipe.title),
            "summary": .string(recipe.summary),
            "sourceType": .string(recipe.sourceType.rawValue),
            "prepMinutes": .integer(recipe.prepMinutes),
            "cookMinutes": .integer(recipe.cookMinutes),
            "baseServings": .integer(recipe.baseServings),
            "tags": .strings(recipe.tags),
            "dishTypes": .strings(recipe.dishTypes),
            "cookware": .strings(recipe.cookware),
            "isFavorite": .boolean(recipe.isFavorite),
            "timesCooked": .integer(recipe.timesCooked),
            "notes": .string(recipe.notes),
        ]
        if let url = recipe.sourceURL { fields["sourceURL"] = .string(url.absoluteString) }
        if let url = recipe.imageURL { fields["imageURL"] = .string(url.absoluteString) }
        if let cooked = recipe.lastCookedAt { fields["lastCookedAt"] = .date(cooked) }
        if let text = Self.json(recipe.nutritionPerServing) { fields["nutrition"] = .string(text) }
        if let text = Self.json(recipe.externalIDs) { fields["externalIDs"] = .string(text) }
        return record(.recipe, recipe, fields)
    }

    private func encode(_ ingredient: Ingredient, in recipe: Recipe) -> SyncRecord {
        var fields: [String: SyncValue] = [
            "recipeID": .uuid(recipe.id),
            "position": .integer(ingredient.position),
            "name": .string(ingredient.name),
            "isOptional": .boolean(ingredient.isOptional),
            "aisle": .string(ingredient.aisle.rawValue),
        ]
        if let id = ingredient.canonicalItemID { fields["canonicalItemID"] = .uuid(id) }
        if let amount = ingredient.quantity { fields["quantity"] = .number(amount) }
        if let unit = ingredient.unit { fields["unit"] = .string(unit.rawValue) }
        if let prep = ingredient.preparation { fields["preparation"] = .string(prep) }
        return record(.ingredient, ingredient, fields)
    }

    private func encode(_ step: RecipeStep, in recipe: Recipe) -> SyncRecord {
        var fields: [String: SyncValue] = [
            "recipeID": .uuid(recipe.id),
            "position": .integer(step.position),
            "text": .string(step.text),
            "ingredientRefs": .uuids(step.ingredientRefs),
        ]
        if let seconds = step.timerSeconds { fields["timerSeconds"] = .integer(seconds) }
        return record(.recipeStep, step, fields)
    }

    /// Small structures travel as JSON in a string.
    ///
    /// `SyncValue` has no case for an object on purpose: every field is one a
    /// reader can look at and understand, and adding a general object would
    /// make the wire format a place to hide things. Two fields genuinely are
    /// structures, so they say so by being text that happens to parse.
    private static func json(_ value: (some Encodable)?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parse<T: Decodable>(_ type: T.Type, from text: String?) -> T? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode(_ entry: PantryEntry) -> SyncRecord {
        record(.pantryEntry, entry, [
            "canonicalItemID": .uuid(entry.canonicalItemID),
            "status": .string(entry.status.rawValue),
        ])
    }

    private func encode(_ plan: MealPlan) -> SyncRecord {
        record(.mealPlan, plan, ["weekStartDate": .date(plan.weekStartDate)])
    }

    private func encode(_ meal: PlannedMeal) -> SyncRecord {
        var fields: [String: SyncValue] = [
            "position": .integer(meal.position),
            "slot": .string(meal.slot.rawValue),
            "recipeID": .uuid(meal.recipeID),
            "servings": .integer(meal.servings),
            "isCooked": .boolean(meal.isCooked),
        ]
        if let date = meal.date { fields["date"] = .date(date) }
        if let plan = meal.plan { fields["planID"] = .uuid(plan.id) }
        return record(.plannedMeal, meal, fields)
    }

    private func encode(_ list: GroceryList) -> SyncRecord {
        var fields: [String: SyncValue] = ["generatedAt": .date(list.generatedAt)]
        if let planID = list.mealPlanID { fields["mealPlanID"] = .uuid(planID) }
        return record(.groceryList, list, fields)
    }

    private func encode(_ item: GroceryItem) -> SyncRecord {
        var fields: [String: SyncValue] = [
            "position": .integer(item.position),
            "displayName": .string(item.displayName),
            "aisle": .string(item.aisle.rawValue),
            "isChecked": .boolean(item.isChecked),
            "isManual": .boolean(item.isManual),
            "sourceRecipeIDs": .uuids(item.sourceRecipeIDs),
            "quantities": .strings(item.quantities.map(Self.text)),
            "manualQuantities": .strings(item.manualQuantities.map(Self.text)),
        ]
        if let id = item.canonicalItemID { fields["canonicalItemID"] = .uuid(id) }
        if let note = item.note { fields["note"] = .string(note) }
        if let list = item.list { fields["listID"] = .uuid(list.id) }
        return record(.groceryItem, item, fields)
    }

    /// A quantity as "2.5 cup", or "2.5" when it has no unit. Two fields would
    /// have meant two parallel arrays that can fall out of step.
    static func text(_ quantity: Quantity) -> String {
        guard let unit = quantity.unit else { return "\(quantity.quantity)" }
        return "\(quantity.quantity) \(unit.rawValue)"
    }

    static func quantity(_ text: String) -> Quantity? {
        let parts = text.split(separator: " ")
        guard let amount = Double(parts.first ?? "") else { return nil }
        let unit = parts.count > 1 ? Unit(rawValue: String(parts[1])) : nil
        return Quantity(amount, unit)
    }
}

// MARK: - In

@MainActor
extension SyncMapper {

    /// Applies what the other phone sent.
    ///
    /// Last writer wins, per record, by `updatedAt`. A record we have touched
    /// more recently than the incoming copy is left alone: that is what stops
    /// an older push from undoing something just done here, and it is why both
    /// sides can write while offline without a merge screen.
    ///
    /// Returns how many were actually taken, which is not the same as how many
    /// arrived, and is what the user sees.
    @discardableResult
    /// Async so it can breathe.
    ///
    /// This runs on the main actor, because the store does. A page of five
    /// hundred records takes about ten seconds, and for all ten of them the
    /// screen does not answer a touch. Yielding between pages was not enough:
    /// one page is the whole freeze. So it yields inside, every fifty records,
    /// which hands the run loop a turn often enough that the phone stays alive
    /// while the work goes on.
    func apply(_ records: [SyncRecord], as householdID: UUID) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        var taken = 0
        var sinceBreath = 0

        // The two tables big enough to matter, read once.
        //
        // `find(id:)` fetches a whole table and scans it, which is fine for
        // twenty pantry entries and ruinous here: every one of eight thousand
        // incoming ingredients was fetching all 427 recipes to find its
        // parent. Two reads up front instead of eight thousand.
        var lookup = Lookup(
            recipes: Dictionary(try recipes.all().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            canonicalItems: Dictionary(try canonicalItems.all().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        )

        // Parents before children: a planned meal arriving before its plan has
        // nothing to attach to. `SyncEntity.allCases` is declared in that
        // order so this cannot be got wrong by accident.
        for entity in SyncEntity.allCases {
            for record in records where record.entity == entity {
                if try applyOne(record, as: householdID, lookup: &lookup) { taken += 1 }

                sinceBreath += 1
                if sinceBreath >= Self.recordsPerBreath {
                    sinceBreath = 0
                    await Task.yield()
                }
            }
        }

        if taken > 0 { try households.save() }
        return taken
    }

    /// How many records go by before the run loop gets a turn. Fifty is about
    /// a fifth of a second of work, which is short enough that a tap lands.
    private static let recordsPerBreath = 50

    /// What this batch has already seen, so a record made a moment ago is
    /// found by the record that refers to it.
    private struct Lookup {
        var recipes: [UUID: Recipe]
        var canonicalItems: [UUID: CanonicalItem]
    }

    private func applyOne(
        _ record: SyncRecord, as householdID: UUID, lookup: inout Lookup
    ) throws -> Bool {
        switch record.entity {
        case .household:
            guard let existing = try households.find(id: record.id) else {
                let household = Household(id: record.id, name: record.string("name") ?? "Our kitchen")
                household.householdID = householdID
                household.updatedAt = record.updatedAt
                households.insert(household)
                return true
            }
            guard record.updatedAt > existing.updatedAt else { return false }
            existing.name = record.string("name") ?? existing.name
            existing.updatedAt = record.updatedAt
            return true

        case .householdPreferences:
            let household = try households.find(id: householdID)
            let existing = household?.preferences
            if let existing, record.updatedAt <= existing.updatedAt { return false }

            let preferences = existing ?? HouseholdPreferences(id: record.id, householdID: householdID)
            preferences.menuType = record.enumeration("menuType") ?? preferences.menuType
            preferences.restrictions = record.enumerations("restrictions") ?? preferences.restrictions
            preferences.dislikedIngredients = record.strings("dislikedIngredients") ?? preferences.dislikedIngredients
            preferences.defaultServings = record.integer("defaultServings") ?? preferences.defaultServings
            preferences.units = record.enumeration("units") ?? preferences.units
            preferences.maxWeeknightMinutes = record.integer("maxWeeknightMinutes") ?? preferences.maxWeeknightMinutes
            preferences.weekStartsOn = record.integer("weekStartsOn") ?? preferences.weekStartsOn
            preferences.aisleOrder = record.enumerations("aisleOrder") ?? preferences.aisleOrder
            preferences.updatedAt = record.updatedAt
            if existing == nil { preferences.household = household }
            return true

        case .user:
            if let existing = try users.find(id: record.id) {
                guard record.updatedAt > existing.updatedAt else { return false }
                existing.displayName = record.string("displayName") ?? existing.displayName
                existing.updatedAt = record.updatedAt
                return true
            }
            let user = User(
                id: record.id,
                householdID: householdID,
                displayName: record.string("displayName") ?? "Someone"
            )
            user.updatedAt = record.updatedAt
            users.insert(user)
            return true

        case .pantryEntry:
            guard let itemID = record.uuid("canonicalItemID"),
                  let status: PantryStatus = record.enumeration("status")
            else { return false }

            if let existing = try pantry.find(id: record.id) {
                guard record.updatedAt > existing.updatedAt else { return false }
                existing.canonicalItemID = itemID
                existing.status = status
                existing.updatedAt = record.updatedAt
                return true
            }
            let entry = PantryEntry(id: record.id, householdID: householdID, canonicalItemID: itemID, status: status)
            entry.updatedAt = record.updatedAt
            pantry.insert(entry)
            return true

        case .mealPlan:
            guard let week = record.date("weekStartDate") else { return false }
            if let existing = try plans.find(id: record.id) {
                guard record.updatedAt > existing.updatedAt else { return false }
                existing.weekStartDate = week
                existing.updatedAt = record.updatedAt
                return true
            }
            let plan = MealPlan(id: record.id, householdID: householdID, weekStartDate: week)
            plan.updatedAt = record.updatedAt
            plans.insert(plan)
            return true

        case .plannedMeal:
            guard let recipeID = record.uuid("recipeID") else { return false }
            let plan = record.uuid("planID").flatMap { try? plans.find(id: $0) } ?? nil

            if let existing = try plans.all().flatMap(\.entries).first(where: { $0.id == record.id }) {
                guard record.updatedAt > existing.updatedAt else { return false }
                existing.position = record.integer("position") ?? existing.position
                existing.slot = record.enumeration("slot") ?? existing.slot
                existing.recipeID = recipeID
                existing.servings = record.integer("servings") ?? existing.servings
                existing.isCooked = record.boolean("isCooked") ?? existing.isCooked
                existing.date = record.date("date")
                existing.updatedAt = record.updatedAt
                return true
            }

            // A meal with no plan here yet is dropped rather than orphaned.
            // The plan is in the same batch and sorts first, so this only
            // happens when a page boundary split them, and the next pull
            // brings it again.
            guard let plan else { return false }
            let meal = PlannedMeal(
                id: record.id,
                householdID: householdID,
                position: record.integer("position") ?? 0,
                date: record.date("date"),
                slot: record.enumeration("slot") ?? .dinner,
                recipeID: recipeID,
                servings: record.integer("servings") ?? 4,
                isCooked: record.boolean("isCooked") ?? false
            )
            meal.updatedAt = record.updatedAt
            meal.plan = plan
            plan.entries.append(meal)
            return true

        case .groceryList:
            guard let generated = record.date("generatedAt") else { return false }
            if let existing = try lists.find(id: record.id) {
                guard record.updatedAt > existing.updatedAt else { return false }
                existing.generatedAt = generated
                existing.mealPlanID = record.uuid("mealPlanID")
                existing.updatedAt = record.updatedAt
                return true
            }
            let list = GroceryList(
                id: record.id,
                householdID: householdID,
                mealPlanID: record.uuid("mealPlanID"),
                generatedAt: generated
            )
            list.updatedAt = record.updatedAt
            lists.insert(list)
            return true

        case .groceryItem:
            let quantities = (record.strings("quantities") ?? []).compactMap(Self.quantity)
            let manual = (record.strings("manualQuantities") ?? []).compactMap(Self.quantity)

            if let existing = try lists.all().flatMap(\.items).first(where: { $0.id == record.id }) {
                guard record.updatedAt > existing.updatedAt else { return false }
                existing.position = record.integer("position") ?? existing.position
                existing.displayName = record.string("displayName") ?? existing.displayName
                existing.canonicalItemID = record.uuid("canonicalItemID")
                existing.aisle = record.enumeration("aisle") ?? existing.aisle
                existing.isChecked = record.boolean("isChecked") ?? existing.isChecked
                existing.isManual = record.boolean("isManual") ?? existing.isManual
                existing.sourceRecipeIDs = record.uuids("sourceRecipeIDs") ?? existing.sourceRecipeIDs
                existing.quantities = quantities
                existing.manualQuantities = manual
                existing.note = record.string("note")
                existing.updatedAt = record.updatedAt
                return true
            }

            guard let listID = record.uuid("listID"), let list = try lists.find(id: listID) else { return false }
            let item = GroceryItem(
                id: record.id,
                householdID: householdID,
                position: record.integer("position") ?? 0,
                canonicalItemID: record.uuid("canonicalItemID"),
                displayName: record.string("displayName") ?? "",
                quantities: quantities,
                manualQuantities: manual,
                aisle: record.enumeration("aisle") ?? .other,
                isChecked: record.boolean("isChecked") ?? false,
                sourceRecipeIDs: record.uuids("sourceRecipeIDs") ?? [],
                isManual: record.boolean("isManual") ?? false,
                note: record.string("note")
            )
            item.updatedAt = record.updatedAt
            item.list = list
            list.items.append(item)
            return true

        case .canonicalItem:
            guard let name = record.string("name"),
                  let aisle: Aisle = record.enumeration("aisle")
            else { return false }

            let aliases = record.strings("aliases") ?? []
            let learned = record.strings("learnedAliases") ?? []
            let isStaple = record.boolean("isStaple") ?? false
            let unit: Unit? = record.enumeration("defaultUnit")

            if let existing = lookup.canonicalItems[record.id] {
                guard record.updatedAt > existing.updatedAt else { return false }
                existing.name = name
                existing.aliases = aliases
                existing.learnedAliases = learned
                existing.aisle = aisle
                existing.isStaple = isStaple
                existing.defaultUnit = unit
                existing.updatedAt = record.updatedAt
                return true
            }
            let item = CanonicalItem(
                id: record.id,
                householdID: householdID,
                name: name,
                aliases: aliases,
                learnedAliases: learned,
                aisle: aisle,
                isStaple: isStaple,
                defaultUnit: unit
            )
            item.updatedAt = record.updatedAt
            canonicalItems.insert(item)
            lookup.canonicalItems[item.id] = item
            return true

        case .recipe:
            guard let title = record.string("title"),
                  let sourceType: RecipeSourceType = record.enumeration("sourceType")
            else { return false }

            let recipe: Recipe
            if let existing = lookup.recipes[record.id] {
                guard record.updatedAt > existing.updatedAt else { return false }
                recipe = existing
            } else {
                recipe = Recipe(
                    id: record.id,
                    householdID: householdID,
                    title: title,
                    sourceType: sourceType,
                    baseServings: record.integer("baseServings") ?? 4
                )
                recipes.insert(recipe)
                lookup.recipes[recipe.id] = recipe
            }

            recipe.title = title
            recipe.summary = record.string("summary") ?? ""
            recipe.sourceType = sourceType
            recipe.sourceURL = record.string("sourceURL").flatMap(URL.init(string:))
            recipe.prepMinutes = record.integer("prepMinutes") ?? 0
            recipe.cookMinutes = record.integer("cookMinutes") ?? 0
            recipe.baseServings = record.integer("baseServings") ?? recipe.baseServings
            recipe.tags = record.strings("tags") ?? []
            recipe.dishTypes = record.strings("dishTypes") ?? []
            recipe.cookware = record.strings("cookware") ?? []
            recipe.imageURL = record.string("imageURL").flatMap(URL.init(string:))
            recipe.isFavorite = record.boolean("isFavorite") ?? false
            recipe.timesCooked = record.integer("timesCooked") ?? 0
            recipe.lastCookedAt = record.date("lastCookedAt")
            recipe.notes = record.string("notes") ?? ""
            recipe.nutritionPerServing = Self.parse(Nutrition.self, from: record.string("nutrition"))
            recipe.externalIDs = Self.parse([String: String].self, from: record.string("externalIDs")) ?? [:]
            // imageData is deliberately untouched. It never travels, and a
            // picture this phone already has must not be wiped by a record
            // that was never carrying one.
            recipe.updatedAt = record.updatedAt
            return true

        case .ingredient:
            guard let name = record.string("name"),
                  let recipeID = record.uuid("recipeID")
            else { return false }
            // Dropped rather than orphaned. The recipe sorts first and is in
            // the same batch, so this only happens when a page boundary split
            // them, and the next pull brings it again.
            guard let recipe = lookup.recipes[recipeID] else { return false }

            let ingredient: Ingredient
            if let existing = recipe.ingredients.first(where: { $0.id == record.id }) {
                guard record.updatedAt > existing.updatedAt else { return false }
                ingredient = existing
            } else {
                ingredient = Ingredient(
                    id: record.id,
                    householdID: householdID,
                    position: record.integer("position") ?? 0,
                    name: name
                )
                recipes.insertIngredient(ingredient)
                ingredient.recipe = recipe
            }

            ingredient.position = record.integer("position") ?? ingredient.position
            ingredient.name = name
            ingredient.canonicalItemID = record.uuid("canonicalItemID")
            ingredient.quantity = record.double("quantity")
            ingredient.unit = record.enumeration("unit")
            ingredient.preparation = record.string("preparation")
            ingredient.isOptional = record.boolean("isOptional") ?? false
            ingredient.aisle = record.enumeration("aisle") ?? .other
            ingredient.updatedAt = record.updatedAt
            return true

        case .recipeStep:
            guard let text = record.string("text"),
                  let recipeID = record.uuid("recipeID")
            else { return false }
            guard let recipe = lookup.recipes[recipeID] else { return false }

            let step: RecipeStep
            if let existing = recipe.steps.first(where: { $0.id == record.id }) {
                guard record.updatedAt > existing.updatedAt else { return false }
                step = existing
            } else {
                step = RecipeStep(
                    id: record.id,
                    householdID: householdID,
                    position: record.integer("position") ?? 0,
                    text: text
                )
                recipes.insertStep(step)
                step.recipe = recipe
            }

            step.position = record.integer("position") ?? step.position
            step.text = text
            step.timerSeconds = record.integer("timerSeconds")
            step.ingredientRefs = record.uuids("ingredientRefs") ?? []
            step.updatedAt = record.updatedAt
            return true
        }
    }

    /// Applies deletions. A record changed here after the other phone deleted
    /// it is kept: bringing something back deliberately beats losing it.
    @discardableResult
    func apply(_ deletions: [SyncDeletion]) throws -> Int {
        var removed = 0

        for deletion in deletions {
            switch deletion.entity {
            case .pantryEntry:
                if let entry = try pantry.find(id: deletion.recordID), entry.updatedAt <= deletion.deletedAt {
                    pantry.delete(entry)
                    removed += 1
                }
            case .plannedMeal:
                if let meal = try plans.all().flatMap(\.entries).first(where: { $0.id == deletion.recordID }),
                   meal.updatedAt <= deletion.deletedAt {
                    meal.plan?.entries.removeAll { $0.id == meal.id }
                    plans.deleteEntry(meal)
                    removed += 1
                }
            case .groceryItem:
                if let item = try lists.all().flatMap(\.items).first(where: { $0.id == deletion.recordID }),
                   item.updatedAt <= deletion.deletedAt {
                    item.list?.items.removeAll { $0.id == item.id }
                    lists.deleteItem(item)
                    removed += 1
                }
            case .mealPlan:
                if let plan = try plans.find(id: deletion.recordID), plan.updatedAt <= deletion.deletedAt {
                    for meal in plan.entries { plans.deleteEntry(meal) }
                    plans.delete(plan)
                    removed += 1
                }
            case .groceryList:
                if let list = try lists.find(id: deletion.recordID), list.updatedAt <= deletion.deletedAt {
                    for item in list.items { lists.deleteItem(item) }
                    lists.delete(list)
                    removed += 1
                }
            case .user:
                if let user = try users.find(id: deletion.recordID), user.updatedAt <= deletion.deletedAt {
                    users.delete(user)
                    removed += 1
                }
            case .household, .householdPreferences:
                // Deleting the household out from under the other phone is not
                // something sync should do on its own.
                continue
            case .canonicalItem:
                if let item = try canonicalItems.find(id: deletion.recordID),
                   item.updatedAt <= deletion.deletedAt {
                    canonicalItems.delete(item)
                    removed += 1
                }
            case .recipe:
                if let recipe = try recipes.find(id: deletion.recordID),
                   recipe.updatedAt <= deletion.deletedAt {
                    for ingredient in Array(recipe.ingredients) { recipes.deleteIngredient(ingredient) }
                    for step in Array(recipe.steps) { recipes.deleteStep(step) }
                    recipes.delete(recipe)
                    removed += 1
                }
            case .ingredient:
                if let ingredient = try recipes.allIngredients().first(where: { $0.id == deletion.recordID }),
                   ingredient.updatedAt <= deletion.deletedAt {
                    recipes.deleteIngredient(ingredient)
                    removed += 1
                }
            case .recipeStep:
                if let step = try recipes.allSteps().first(where: { $0.id == deletion.recordID }),
                   step.updatedAt <= deletion.deletedAt {
                    recipes.deleteStep(step)
                    removed += 1
                }
            }
        }

        if removed > 0 { try households.save() }
        return removed
    }
}

// MARK: - Reading fields

private extension SyncRecord {
    func string(_ key: String) -> String? {
        if case .string(let value) = fields[key] { return value }
        return nil
    }

    func integer(_ key: String) -> Int? {
        switch fields[key] {
        case .integer(let value): value
        case .number(let value): Int(value)
        default: nil
        }
    }

    func boolean(_ key: String) -> Bool? {
        if case .boolean(let value) = fields[key] { return value }
        return nil
    }

    func double(_ key: String) -> Double? {
        switch fields[key] {
        case .number(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }

    /// Both spellings, and that is not belt and braces.
    ///
    /// The encoder writes `.uuid`, and everything that goes over the wire is
    /// turned into text on the way out and comes back as `.string`, so only
    /// the string case was ever exercised. Which meant the mapper could not
    /// read back a record it had just written: every id came back nil and
    /// every record was dropped, silently, by a guard that looks like
    /// ordinary validation. It cost an afternoon of reading the engine.
    func uuid(_ key: String) -> UUID? {
        switch fields[key] {
        case .uuid(let value): value
        case .string(let value): UUID(uuidString: value)
        default: nil
        }
    }

    func uuids(_ key: String) -> [UUID]? {
        switch fields[key] {
        case .uuids(let values): values
        case .strings(let values): values.compactMap(UUID.init(uuidString:))
        default: nil
        }
    }

    func strings(_ key: String) -> [String]? {
        if case .strings(let values) = fields[key] { return values }
        return nil
    }

    func date(_ key: String) -> Date? {
        switch fields[key] {
        case .date(let value): value
        case .string(let value): SupabaseSyncClient.date(from: value)
        default: nil
        }
    }

    func enumeration<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
        guard case .string(let value) = fields[key] else { return nil }
        return T(rawValue: value)
    }

    func enumerations<T: RawRepresentable>(_ key: String) -> [T]? where T.RawValue == String {
        guard case .strings(let values) = fields[key] else { return nil }
        return values.compactMap(T.init(rawValue:))
    }
}
