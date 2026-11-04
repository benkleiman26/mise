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

    func run() async {
        guard status != .working else { return }
        status = .working

        do {
            guard let householdID = try households.all().first?.id else { throw SyncError.noHousehold }

            // Out.
            let outgoing = SyncBatch(
                records: try mapper.records(changedSince: cursor),
                deletions: try pendingDeletions(householdID: householdID)
            )
            if !outgoing.records.isEmpty || !outgoing.deletions.isEmpty {
                _ = try await client.push(outgoing, householdID: householdID, deviceID: deviceID)
                try clearSentDeletions(outgoing.deletions)
            }
            lastSent = outgoing.records.count + outgoing.deletions.count

            // In.
            let incoming = try await client.pull(householdID: householdID, since: cursor, deviceID: deviceID)
            // Deletions last: a record that arrives and is then deleted in the
            // same round should end up deleted, not resurrected.
            let taken = try mapper.apply(incoming.records)
            let removed = try mapper.apply(incoming.deletions)
            lastReceived = taken + removed

            if let moved = incoming.cursor { cursor = moved }
            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: Self.syncedKey)
            status = .idle
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// Starts this device over: everything is sent and everything is taken.
    /// For after a restore, or when the two phones have plainly drifted.
    func resetCursor() {
        cursor = nil
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
