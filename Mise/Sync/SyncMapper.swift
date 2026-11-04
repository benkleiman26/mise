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
    let pantry: any PantryRepository
    let plans: any MealPlanRepository
    let lists: any GroceryListRepository

    // MARK: - Out

    func records(changedSince cursor: Date?) throws -> [SyncRecord] {
        var out: [SyncRecord] = []
        let after = cursor ?? .distantPast

        for household in try households.all() where household.updatedAt > after {
            out.append(encode(household))
            if let preferences = household.preferences, preferences.updatedAt > after {
                out.append(encode(preferences))
            }
        }
        for user in try users.all() where user.updatedAt > after {
            out.append(encode(user))
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
    func apply(_ records: [SyncRecord], as householdID: UUID) throws -> Int {
        var taken = 0

        // Parents before children: a planned meal arriving before its plan has
        // nothing to attach to. `SyncEntity.allCases` is declared in that
        // order so this cannot be got wrong by accident.
        for entity in SyncEntity.allCases {
            for record in records where record.entity == entity {
                if try applyOne(record, as: householdID) { taken += 1 }
            }
        }

        if taken > 0 { try households.save() }
        return taken
    }

    private func applyOne(_ record: SyncRecord, as householdID: UUID) throws -> Bool {
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

        case .canonicalItem, .recipe, .ingredient, .recipeStep:
            // Not shared. See SyncEntity.isShared.
            return false
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
            case .canonicalItem, .recipe, .ingredient, .recipeStep:
                continue
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

    func uuid(_ key: String) -> UUID? {
        guard case .string(let value) = fields[key] else { return nil }
        return UUID(uuidString: value)
    }

    func uuids(_ key: String) -> [UUID]? {
        guard case .strings(let values) = fields[key] else { return nil }
        return values.compactMap(UUID.init(uuidString:))
    }

    func strings(_ key: String) -> [String]? {
        if case .strings(let values) = fields[key] { return values }
        return nil
    }

    func date(_ key: String) -> Date? {
        guard case .string(let value) = fields[key] else { return nil }
        return SupabaseSyncClient.date(from: value)
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
