import Foundation

/// Section 5.4. Reads the pantry, joins it to the canonical item table because
/// a `PantryEntry` stores only an id, and changes what the household has.
///
/// A status that cannot be changed is worse than no pantry at all: the staples
/// are seeded once at install and then the list silently leaves out eggs
/// forever, whether or not there are any.
@MainActor
@Observable
final class PantryStore {
    /// One row, flattened for display.
    struct Row: Identifiable, Sendable {
        /// The pantry entry's id, or the canonical item's when nothing is
        /// recorded for it yet.
        let id: UUID
        let canonicalItemID: UUID
        let name: String
        let aisle: Aisle
        /// Nil when the household has never said anything about this item,
        /// which is most of the 395 and is not the same as being out of it.
        let status: PantryStatus?
    }

    /// One aisle's worth of rows, in the household's store walk order.
    struct AisleGroup: Identifiable, Sendable {
        var id: Aisle { aisle }
        let aisle: Aisle
        let rows: [Row]
    }

    /// A candidate for the add sheet: anything in the grocery table, whether
    /// or not the household tracks it.
    struct Suggestion: Identifiable, Sendable {
        let id: UUID
        let name: String
        let aisle: Aisle
        /// Already has a status, so adding it again would only change that.
        let isTracked: Bool
        /// The spelling that matched, when it was not the item's own name.
        /// Worth showing: somebody typing "scallion" should understand why
        /// they are being offered "green onion".
        let matchedOn: String?
    }

    private let pantry: any PantryRepository
    private let canonicalItems: any CanonicalItemRepository
    private let households: any HouseholdRepository

    private(set) var groups: [AisleGroup] = []
    private(set) var loadProblem: String?

    /// Showing all 395 grocery items by default would bury the twenty the
    /// household actually tracks, so the extra ones arrive through the search.
    var query: String = ""
    var showsEverything = false

    init(
        pantry: any PantryRepository,
        canonicalItems: any CanonicalItemRepository,
        households: any HouseholdRepository
    ) {
        self.pantry = pantry
        self.canonicalItems = canonicalItems
        self.households = households
    }

    var isEmpty: Bool { groups.isEmpty }

    func load() {
        do {
            let items = try canonicalItems.all()
            var statusByItem: [UUID: PantryEntry] = [:]
            for entry in try pantry.all() {
                statusByItem[entry.canonicalItemID] = entry
            }

            let terms = query
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)

            var rowsByAisle: [Aisle: [Row]] = [:]
            for item in items {
                let entry = statusByItem[item.id]

                if terms.isEmpty {
                    // Without a search, only what the household actually
                    // tracks, unless they have asked for the whole table.
                    guard showsEverything || entry != nil else { continue }
                } else {
                    let haystack = ([item.name] + item.aliases + item.learnedAliases)
                        .joined(separator: " ")
                        .lowercased()
                    guard terms.allSatisfy({ haystack.contains($0) }) else { continue }
                }

                rowsByAisle[item.aisle, default: []].append(
                    Row(
                        id: entry?.id ?? item.id,
                        canonicalItemID: item.id,
                        name: item.name,
                        aisle: item.aisle,
                        status: entry?.status
                    )
                )
            }

            let order = try aisleOrder()
            groups = order.compactMap { aisle in
                guard let rows = rowsByAisle[aisle], !rows.isEmpty else { return nil }
                return AisleGroup(
                    aisle: aisle,
                    rows: rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
            loadProblem = nil
        } catch {
            groups = []
            loadProblem = "The pantry could not be read. \(error)"
        }
    }

    /// Sets what the household has, creating the record when there is none.
    ///
    /// Passing nil means "stop tracking this", which deletes the record rather
    /// than inventing a third state, because an item nobody has said anything
    /// about and an item deliberately marked as out are different things to the
    /// list generator.
    func set(_ status: PantryStatus?, for row: Row) {
        do {
            let existing = try pantry.all().first { $0.canonicalItemID == row.canonicalItemID }

            switch (status, existing) {
            case (nil, let entry?):
                pantry.delete(entry)
            case (nil, nil):
                break
            case (let status?, let entry?):
                entry.status = status
                entry.updatedAt = .now
            case (let status?, nil):
                guard let householdID = try households.all().first?.id else { return }
                pantry.insert(
                    PantryEntry(
                        id: StableID.pantryEntry(householdID: householdID, canonicalItemID: row.canonicalItemID),
                        householdID: householdID,
                        canonicalItemID: row.canonicalItemID,
                        status: status
                    )
                )
            }

            try pantry.save()
            load()
        } catch {
            loadProblem = "That could not be saved. \(error)"
        }
    }

    // MARK: - Adding

    /// Everything in the grocery table that matches what has been typed.
    ///
    /// Searches the shipped spellings and the learned ones as well as the
    /// name, because the table already knows that a scallion is a green
    /// onion, and a person who has to find that out by guessing will add a
    /// second row for it instead.
    func suggestions(for text: String) -> [Suggestion] {
        let terms = SeedCatalog.key(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        do {
            let tracked = Set(try pantry.all().map(\.canonicalItemID))
            return try canonicalItems.all()
                .compactMap { item -> Suggestion? in
                    let spellings = item.aliases + item.learnedAliases
                    let name = SeedCatalog.key(item.name)
                    let matchesName = terms.allSatisfy { name.contains($0) }
                    let spelling = spellings.first { alias in
                        let key = SeedCatalog.key(alias)
                        return terms.allSatisfy { key.contains($0) }
                    }
                    guard matchesName || spelling != nil else { return nil }
                    return Suggestion(
                        id: item.id,
                        name: item.name,
                        aisle: item.aisle,
                        isTracked: tracked.contains(item.id),
                        matchedOn: matchesName ? nil : spelling
                    )
                }
                .sorted { lhs, rhs in
                    // An exact name first, then the shorter name, which is
                    // nearly always the more general item: "rice" above
                    // "rice vinegar" for somebody who typed "rice".
                    let left = SeedCatalog.key(lhs.name), right = SeedCatalog.key(rhs.name)
                    let typed = SeedCatalog.key(text)
                    if (left == typed) != (right == typed) { return left == typed }
                    if left.count != right.count { return left.count < right.count }
                    return left < right
                }
        } catch {
            // Deliberately silent. This runs while the add sheet's body is
            // being evaluated, and writing to observable state from there is
            // a change during view update. An empty list says enough.
            return []
        }
    }

    /// Whether this spelling is already claimed, by a name or by an alias.
    ///
    /// Names and aliases share one namespace and `tools/resource-lint`
    /// enforces that, because section 5.3 looks a string up in both and a
    /// string claimed twice is ambiguous at exactly the step every merge
    /// depends on. The add sheet must not be the one hole in that rule.
    func isNameTaken(_ text: String) -> Bool {
        let key = SeedCatalog.key(text)
        guard !key.isEmpty else { return true }
        do {
            return try canonicalItems.all().contains { item in
                SeedCatalog.key(item.name) == key
                    || (item.aliases + item.learnedAliases).contains { SeedCatalog.key($0) == key }
            }
        } catch {
            return true
        }
    }

    /// Starts tracking something the table already knows.
    func track(_ suggestion: Suggestion, as status: PantryStatus) {
        set(status, for: Row(
            id: suggestion.id,
            canonicalItemID: suggestion.id,
            name: suggestion.name,
            aisle: suggestion.aisle,
            status: nil
        ))
    }

    /// Adds an item the table has never heard of, and tracks it.
    ///
    /// The id comes from the name rather than being generated, the same way
    /// seeding derives one, so that two phones which both add "gochujang"
    /// end up with one item and not two.
    ///
    /// Returns false and says why when the name is already claimed.
    @discardableResult
    func addItem(named name: String, aisle: Aisle, status: PantryStatus) -> Bool {
        let cleaned = SeedCatalog.key(name)
        guard !cleaned.isEmpty else { return false }
        guard !isNameTaken(cleaned) else {
            loadProblem = "Mise already has an item called \"\(cleaned)\". Search for it instead."
            return false
        }

        do {
            guard let householdID = try households.all().first?.id else { return false }
            let item = CanonicalItem(
                id: StableID.canonicalItem(name: cleaned),
                householdID: householdID,
                name: cleaned,
                aisle: aisle
            )
            canonicalItems.insert(item)
            try canonicalItems.save()

            set(status, for: Row(
                id: item.id,
                canonicalItemID: item.id,
                name: item.name,
                aisle: item.aisle,
                status: nil
            ))
            return true
        } catch {
            loadProblem = "That could not be saved. \(error)"
            return false
        }
    }

    /// The household's own store walk order, falling back to the default.
    private func aisleOrder() throws -> [Aisle] {
        let stored = try households.all().first?.preferences?.aisleOrder ?? []
        guard !stored.isEmpty else { return Aisle.allCases }
        let missing = Aisle.allCases.filter { !stored.contains($0) }
        return stored + missing
    }
}
