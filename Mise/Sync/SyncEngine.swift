import Foundation
import SwiftData

/// One round of sync: send what changed here, take what changed there.
///
/// Push before pull, on purpose. If the pull came first, a record edited here
/// and there since the last round would be overwritten locally and the local
/// edit would never reach the server, so it would be lost rather than merely
/// losing. Pushing first means the newer of the two wins on the server and
/// both phones end up agreeing with it.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case idle
        case working
        case failed(String)
    }

    private let client: any SyncClient
    private let mapper: SyncMapper
    private let households: any HouseholdRepository
    private let context: ModelContext
    private let deviceID: UUID

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?
    private(set) var lastSent = 0
    private(set) var lastReceived = 0

    private static let cursorKey = "mise.sync.cursor"
    private static let sentKey = "mise.sync.sentUpTo"
    private static let syncedKey = "mise.sync.lastSyncedAt"

    init(
        client: any SyncClient,
        mapper: SyncMapper,
        households: any HouseholdRepository,
        context: ModelContext,
        deviceID: UUID = DeviceIdentity.current
    ) {
        self.client = client
        self.mapper = mapper
        self.households = households
        self.context = context
        self.deviceID = deviceID
        self.lastSyncedAt = UserDefaults.standard.object(forKey: Self.syncedKey) as? Date
    }

    /// Where this device got to, by the server's clock.
    ///
    /// Per device rather than synced, which is the point: it records what this
    /// phone has seen, and a phone restored from a backup should sync again
    /// rather than assume it is up to date.
    private var cursor: Date? {
        get { UserDefaults.standard.object(forKey: Self.cursorKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.cursorKey) }
    }

    /// How far this device has got through its own changes, by its own clock.
    ///
    /// Separate from `cursor`, and the two must never be confused. `cursor` is
    /// a server timestamp, and the records waiting to be sent are stamped by
    /// this phone. Using one to filter the other compares two clocks that
    /// disagree, sometimes by minutes: a phone running behind the server would
    /// decide its own fresh edits were older than the last thing it heard
    /// about and never send them at all, silently, forever.
    private var sentUpTo: Date? {
        get { UserDefaults.standard.object(forKey: Self.sentKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.sentKey) }
    }

    func run() async {
        guard status != .working else { return }
        status = .working

        do {
            // Two different ids, and conflating them was the first thing to
            // fail against the real server.
            //
            // `group` is what the server partitions by and what the row level
            // security policies check membership of. `local` is this
            // database's own household id, which comes from a constant string
            // and is therefore the same on every install of Mise. Pushing
            // under `local` was rejected, correctly: nobody is a member of a
            // household whose id everyone has.
            guard let group = SyncGroup.current else { throw SyncError.notSharing }
            guard let local = try households.all().first?.id else { throw SyncError.noHousehold }

            lastSent = 0
            lastReceived = 0

            // A phone that has never synced pulls first.
            //
            // Push before pull is right everywhere else: a record edited here
            // and there since the last round would otherwise be overwritten
            // locally and the local edit would never reach the server, so it
            // would be lost rather than merely losing. None of that applies on
            // the first round, because this device has never seen the server
            // and so holds no edit the server also has. What it does hold is a
            // database full of seeded defaults, and handing those to an
            // established household before looking at it is how a joining
            // phone overwrites a year of somebody's pantry with its own
            // factory settings.
            if cursor == nil {
                try await pull(group: group, local: local)
            }

            // Out. Filtered by this device's own clock, never by the server
            // cursor, and only advanced once the server has actually taken it.
            let reachedBy = Date()
            let outgoing = SyncBatch(
                records: try mapper.records(changedSince: sentUpTo),
                deletions: try pendingDeletions(householdID: local)
            )
            if !outgoing.records.isEmpty || !outgoing.deletions.isEmpty {
                _ = try await client.push(outgoing, householdID: group, deviceID: deviceID)
                try clearSentDeletions(outgoing.deletions)
            }
            // Stamped from before the batch was gathered, so anything edited
            // while the push was in flight goes next time rather than never.
            sentUpTo = reachedBy
            lastSent = outgoing.records.count + outgoing.deletions.count

            // In.
            try await pull(group: group, local: local)

            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: Self.syncedKey)
            status = .idle
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// One pull, applied and counted.
    ///
    /// Deletions last: a record that arrives and is then deleted in the same
    /// round should end up deleted, not resurrected. Records arrive stamped
    /// with the group id and are stored under this database's own household
    /// id, so everything local agrees about which household it belongs to.
    private func pull(group: UUID, local: UUID) async throws {
        let incoming = try await client.pull(householdID: group, since: cursor, deviceID: deviceID)
        let taken = try mapper.apply(incoming.records, as: local)
        let removed = try mapper.apply(incoming.deletions)
        lastReceived += taken + removed
        if let moved = incoming.cursor { cursor = moved }
    }

    var cursorDescription: String {
        cursor.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "nothing yet"
    }

    /// What a sync would send right now, without sending it.
    func pendingCount() throws -> Int {
        try mapper.records(changedSince: sentUpTo).count
    }

    /// Starts this device over: everything is sent and everything is taken.
    /// For after a restore, or when the two phones have plainly drifted.
    func resetCursor() {
        cursor = nil
        sentUpTo = nil
    }

    // MARK: - Deletions

    private func pendingDeletions(householdID: UUID) throws -> [SyncDeletion] {
        try context.fetch(FetchDescriptor<Deletion>())
            .filter { $0.householdID == householdID && $0.deviceID == deviceID }
            .compactMap { tombstone in
                guard let kind = tombstone.kind, kind.isShared else { return nil }
                return SyncDeletion(
                    entity: kind,
                    recordID: tombstone.recordID,
                    householdID: tombstone.householdID,
                    deletedAt: tombstone.createdAt,
                    deviceID: tombstone.deviceID
                )
            }
    }

    /// Tombstones are rubbish once the server has them: the server keeps its
    /// own copy and tells every other device. Holding onto them locally would
    /// mean resending the same deletions forever.
    private func clearSentDeletions(_ sent: [SyncDeletion]) throws {
        let ids = Set(sent.map(\.recordID))
        for tombstone in try context.fetch(FetchDescriptor<Deletion>())
        where ids.contains(tombstone.recordID) && tombstone.deviceID == deviceID {
            context.delete(tombstone)
        }
        try households.save()
    }
}
