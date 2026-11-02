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

    /// The household's own store walk order, falling back to the default.
    private func aisleOrder() throws -> [Aisle] {
        let stored = try households.all().first?.preferences?.aisleOrder ?? []
        guard !stored.isEmpty else { return Aisle.allCases }
        let missing = Aisle.allCases.filter { !stored.contains($0) }
        return stored + missing
    }
}
