import Foundation

/// Reads the pantry and joins it to the canonical item table, because a
/// `PantryEntry` stores only an id and the screen needs a name and an aisle.
/// Doing the join here keeps it out of the view, per section 11.
@MainActor
@Observable
final class PantryStore {
    /// One row, flattened for display.
    struct Row: Identifiable, Sendable {
        let id: UUID
        let name: String
        let aisle: Aisle
        let status: PantryStatus
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
            var itemsByID: [UUID: CanonicalItem] = [:]
            for item in try canonicalItems.all() {
                itemsByID[item.id] = item
            }

            var rowsByAisle: [Aisle: [Row]] = [:]
            for entry in try pantry.all() {
                guard let item = itemsByID[entry.canonicalItemID] else { continue }
                rowsByAisle[item.aisle, default: []].append(
                    Row(id: entry.id, name: item.name, aisle: item.aisle, status: entry.status)
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

    /// The household's own store walk order, falling back to the default.
    private func aisleOrder() throws -> [Aisle] {
        let stored = try households.all().first?.preferences?.aisleOrder ?? []
        guard !stored.isEmpty else { return Aisle.allCases }
        let missing = Aisle.allCases.filter { !stored.contains($0) }
        return stored + missing
    }
}
