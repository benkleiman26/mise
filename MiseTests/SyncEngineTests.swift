import XCTest
import SwiftData
@testable import Mise

/// The engine had no tests at all, which is the wrong place to have none: what
/// it gets wrong it gets wrong quietly, by not fetching something, and the
/// first sign is a phone missing a meal nobody can explain.
@MainActor
final class SyncEngineTests: XCTestCase {
    /// A server that hands out pages and remembers what it was asked for.
    final class FakeServer: SyncClient, @unchecked Sendable {
        var records: [(seq: Int, record: SyncRecord)] = []
        var deletions: [(seq: Int, deletion: SyncDeletion)] = []
        var pageSize = 2

        private(set) var asked: [SyncCursor] = []
        private(set) var pushed: [SyncBatch] = []
        /// In order, so a test can say which came first rather than infer it.
        private(set) var log: [String] = []

        func pull(householdID: UUID, since: SyncCursor, deviceID: UUID) async throws -> SyncBatch {
            asked.append(since)
            log.append("pull")

            let r = records.filter { $0.seq > since.records }.prefix(pageSize)
            let d = deletions.filter { $0.seq > since.deletions }.prefix(pageSize)

            var batch = SyncBatch()
            batch.records = r.map(\.record)
            batch.deletions = d.map(\.deletion)
            batch.cursor = SyncCursor(
                records: r.map(\.seq).max() ?? since.records,
                deletions: d.map(\.seq).max() ?? since.deletions
            )
            batch.hasMore = r.count >= pageSize || d.count >= pageSize
            return batch
        }

        func push(_ batch: SyncBatch, householdID: UUID, deviceID: UUID) async throws -> Date {
            pushed.append(batch)
            log.append("push")
            return Date()
        }
    }

    private var container: ModelContainer!
    private var context: ModelContext!
    private var households: SwiftDataHouseholdRepository!
    private var server: FakeServer!
    private var engine: SyncEngine!

    private let householdID = StableID.household()

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "mise.sync.cursor.v2")
        UserDefaults.standard.removeObject(forKey: "mise.sync.sentUpTo")
        UserDefaults.standard.removeObject(forKey: "mise.sync.sharedSetVersion")

        container = try MiseSchema.makeContainer(inMemory: true)
        context = ModelContext(container)
        households = SwiftDataHouseholdRepository(context: context)
        households.insert(Household(id: householdID, name: "Test"))
        try households.save()

        server = FakeServer()
        engine = SyncEngine(
            client: server,
            mapper: SyncMapper(
                households: households,
                users: SwiftDataUserRepository(context: context),
                canonicalItems: SwiftDataCanonicalItemRepository(context: context),
                recipes: SwiftDataRecipeRepository(context: context),
                pantry: SwiftDataPantryRepository(context: context),
                plans: SwiftDataMealPlanRepository(context: context),
                lists: SwiftDataGroceryListRepository(context: context)
            ),
            households: households,
            context: context,
            deviceID: UUID()
        )
        SyncGroup.adopt(UUID())
    }

    override func tearDown() async throws {
        engine = nil
        server = nil
        households = nil
        context = nil
        container = nil
        UserDefaults.standard.removeObject(forKey: "mise.sync.cursor.v2")
        UserDefaults.standard.removeObject(forKey: "mise.sync.sentUpTo")
        UserDefaults.standard.removeObject(forKey: "mise.sync.sharedSetVersion")
        SyncGroup.leave()
        try await super.tearDown()
    }

    /// A pantry entry, because it is the simplest shared record there is.
    private func entry(_ seq: Int) -> (seq: Int, record: SyncRecord) {
        (seq, SyncRecord(
            entity: .pantryEntry,
            id: UUID(),
            householdID: householdID,
            updatedAt: Date(timeIntervalSince1970: Double(seq)),
            fields: [
                "canonicalItemID": .uuid(UUID()),
                "status": .string(PantryStatus.have.rawValue),
                "createdAt": .date(Date(timeIntervalSince1970: 0)),
            ]
        ))
    }

    private func tombstone(_ seq: Int) -> (seq: Int, deletion: SyncDeletion) {
        (seq, SyncDeletion(
            entity: .pantryEntry,
            recordID: UUID(),
            householdID: householdID,
            deletedAt: Date(timeIntervalSince1970: Double(seq)),
            deviceID: UUID()
        ))
    }

    // MARK: - Draining

    /// A page is 500 rows on the real server and a first sync is several
    /// thousand. Stopping after one page leaves the rest to arrive whenever
    /// somebody happens to tap the button again, and nothing tells them to.
    func testItKeepsPullingUntilThereIsNothingLeft() async {
        server.records = (1...5).map(entry)

        await engine.run()

        XCTAssertEqual(try? context.fetchCount(FetchDescriptor<PantryEntry>()), 5)
        XCTAssertGreaterThan(server.asked.count, 1, "five rows at two a page is more than one request")
    }

    /// The bug this cursor exists to prevent. Under one shared mark, a full
    /// page of records and a shorter page of deletions reaching further moved
    /// the mark to the further one, and every record in between was skipped
    /// for good.
    func testAShortPageOfDeletionsDoesNotSkipRecords() async {
        server.records = (1...6).map(entry)
        server.deletions = [tombstone(99)]

        await engine.run()

        XCTAssertEqual(try? context.fetchCount(FetchDescriptor<PantryEntry>()), 6,
                       "the deletions reaching sequence 99 must not carry the records past 6")
    }

    func testEachTableKeepsItsOwnPlace() async {
        server.records = (1...3).map(entry)
        server.deletions = [tombstone(1)]

        await engine.run()

        let last = server.asked.last
        XCTAssertEqual(last?.records, 3)
        XCTAssertEqual(last?.deletions, 1)
    }

    /// A loop that depends on the far end agreeing to stop is a loop that
    /// hangs the app when it does not.
    func testItStopsWhenTheCursorDoesNotMove() async {
        server.records = (1...4).map(entry)

        await engine.run()
        let first = server.asked.count

        await engine.run()

        XCTAssertLessThanOrEqual(server.asked.count - first, 2,
                                 "with nothing new, a round asks once and stops")
    }

    // MARK: - Order

    /// A device that has never synced holds no edit the server also has, so
    /// there is nothing for a pull to overwrite. What it does hold is a
    /// database full of seeded defaults, and pushing those at an established
    /// household first is how a joining phone hands it factory settings.
    func testAFirstSyncReadsBeforeItWrites() async {
        server.records = [entry(1)]

        await engine.run()

        XCTAssertEqual(server.log.first, "pull", "it looked before it spoke")
        XCTAssertEqual(server.asked.first, SyncCursor(), "and started from the beginning")
    }

    func testItReportsWhatItTook() async {
        server.records = (1...3).map(entry)

        await engine.run()

        XCTAssertEqual(engine.lastReceived, 3)
        XCTAssertEqual(engine.status, .idle)
    }

    // MARK: - Sending

    /// The first round after the recipe library joined the shared set is
    /// around eight thousand rows. One request carrying all of them is a
    /// multi-megabyte body that times out and takes the round with it.
    func testItSendsInPages() async throws {
        let items = SwiftDataCanonicalItemRepository(context: context)
        for index in 0..<600 {
            items.insert(CanonicalItem(householdID: householdID, name: "item \(index)", aisle: .other))
        }
        try items.save()

        await engine.run()

        XCTAssertGreaterThan(server.pushed.count, 1)
        XCTAssertTrue(
            server.pushed.allSatisfy { $0.records.count <= SyncEngine.pageSize },
            "no request carries more than a page"
        )
        XCTAssertGreaterThanOrEqual(
            server.pushed.reduce(0) { $0 + $1.records.count }, 600,
            "and between them they carry everything"
        )
    }

    // MARK: - Reading back what was written

    /// The mapper could not read a record it had just written. The encoder
    /// spells an id `.uuid` and the reader only accepted `.string`, which is
    /// what the wire produces, so the gap never showed on a real sync and
    /// swallowed every record in a test that built one by hand. A guard that
    /// returns false reads as validation rather than as a bug.
    func testARecordSurvivesBeingWrittenAndReadBack() throws {
        let items = SwiftDataCanonicalItemRepository(context: context)
        let pantryRepository = SwiftDataPantryRepository(context: context)
        let mapper = SyncMapper(
            households: households,
            users: SwiftDataUserRepository(context: context),
            canonicalItems: items,
            recipes: SwiftDataRecipeRepository(context: context),
            pantry: pantryRepository,
            plans: SwiftDataMealPlanRepository(context: context),
            lists: SwiftDataGroceryListRepository(context: context)
        )

        let item = CanonicalItem(householdID: householdID, name: "gochujang", aisle: .international)
        items.insert(item)
        let entry = PantryEntry(householdID: householdID, canonicalItemID: item.id, status: .low)
        pantryRepository.insert(entry)
        try pantryRepository.save()

        let written = try mapper.records(changedSince: nil)
        let pantryRecord = try XCTUnwrap(written.first { $0.entity == .pantryEntry })

        // Removed here, then handed back exactly as it was sent.
        pantryRepository.delete(entry)
        try pantryRepository.save()
        XCTAssertEqual(try pantryRepository.count(), 0)

        let taken = try mapper.apply([pantryRecord], as: householdID)

        XCTAssertEqual(taken, 1, "the mapper has to be able to read its own handwriting")
        let restored = try XCTUnwrap(pantryRepository.all().first)
        XCTAssertEqual(restored.canonicalItemID, item.id)
        XCTAssertEqual(restored.status, .low)
    }
}
