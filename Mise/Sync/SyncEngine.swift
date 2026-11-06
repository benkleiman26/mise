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

    // A new key, because what it holds is no longer a date. A device carrying
    // the old one starts from the beginning, reads everything once and settles,
    // which costs a slow first sync and nothing else.
    private static let cursorKey = "mise.sync.cursor.v2"
    private static let sentKey = "mise.sync.sentUpTo"
    private static let syncedKey = "mise.sync.lastSyncedAt"
    private static let sharedSetKey = "mise.sync.sharedSetVersion"

    /// Bumped whenever the set of things that travel grows, or when what has
    /// already been sent has to go again.
    ///
    /// Raised to 3 after a re-import recorded a deletion for every recipe it
    /// replaced. The tombstones blocked the replacements at the server, so 26
    /// recipes existed on one phone and nowhere else. Once the tombstones are
    /// cleared, this is what sends the recipes back up.
    ///
    /// A device only sends what changed since it last sent, and a recipe
    /// imported in October has not changed since. Without this, the library
    /// joining the shared set would mean the library never going anywhere:
    /// every row in it is older than the watermark. Bumping the number makes
    /// the next round start from the beginning once, and the server's upsert
    /// makes that cost nothing but time.
    private static let sharedSetVersion = 3

    /// How many records go in one request, out or in. A multi-megabyte body
    /// times out and takes the whole round with it.
    static let pageSize = 500

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
    private var cursor: SyncCursor {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.cursorKey),
                  let stored = try? JSONDecoder().decode(SyncCursor.self, from: data)
            else { return SyncCursor() }
            return stored
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.cursorKey) }
    }

    /// How far this device has got through its own changes, by its own clock.
    ///
    /// Separate from `cursor`, and the two must never be confused. `cursor` is
    /// a position in the server's own sequence and says nothing about time at
    /// all; the records waiting to be sent are stamped by this phone's clock.
    /// It was a server timestamp once, and filtering one by the other compared
    /// two clocks that disagree, sometimes by minutes: a phone running behind
    /// the server decided its own fresh edits were older than the last thing
    /// it had heard about and never sent them, silently, forever.
    private var sentUpTo: Date? {
        get { UserDefaults.standard.object(forKey: Self.sentKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.sentKey) }
    }

    /// One round.
    ///
    /// `pages` bounds how much it will take in before stopping, because
    /// applying records happens on the main actor and a phone that has eight
    /// thousand waiting will sit there, frozen, until they are all in. An
    /// automatic round takes a few pages and leaves the rest for the next one;
    /// the button takes everything, because somebody is watching it and knows
    /// why it is busy.
    func run(pages: Int = maximumPages) async {
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
            if cursor.isStart {
                try await drain(group: group, local: local, pages: pages)
            }

            // Everything goes again when the shared set has grown.
            if UserDefaults.standard.integer(forKey: Self.sharedSetKey) != Self.sharedSetVersion {
                sentUpTo = nil
                UserDefaults.standard.set(Self.sharedSetVersion, forKey: Self.sharedSetKey)
            }

            // Out. Filtered by this device's own clock, never by the server
            // cursor, and only advanced once the server has actually taken it.
            let reachedBy = Date()
            let outgoingRecords = try mapper.records(changedSince: sentUpTo)
            let outgoingDeletions = try pendingDeletions(householdID: local)

            // In pages, because the first round after the library joined the
            // shared set is around eight thousand rows and one request
            // carrying all of them is a body nothing on either end wants.
            for start in stride(from: 0, to: outgoingRecords.count, by: Self.pageSize) {
                let end = min(start + Self.pageSize, outgoingRecords.count)
                _ = try await client.push(
                    SyncBatch(records: Array(outgoingRecords[start..<end])),
                    householdID: group,
                    deviceID: deviceID
                )
            }

            if !outgoingDeletions.isEmpty {
                _ = try await client.push(
                    SyncBatch(deletions: outgoingDeletions),
                    householdID: group,
                    deviceID: deviceID
                )
                try clearSentDeletions(outgoingDeletions)
            }

            // Stamped from before the batch was gathered, so anything edited
            // while the push was in flight goes next time rather than never.
            sentUpTo = reachedBy
            lastSent = outgoingRecords.count + outgoingDeletions.count

            // In.
            try await drain(group: group, local: local, pages: pages)

            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: Self.syncedKey)
            status = .idle
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    /// Pulls until there is nothing left, not one page and done.
    ///
    /// A page is 500 rows and a first sync is several thousand, so stopping
    /// after one page would mean the rest arrives whenever somebody happens to
    /// tap the button again. Nothing tells them to.
    ///
    /// Deletions are applied after records within each page: a record that
    /// arrives and is then deleted in the same round should end up deleted,
    /// not resurrected. Records arrive stamped with the group id and are
    /// stored under this database's own household id, so everything local
    /// agrees about which household it belongs to.
    private func drain(group: UUID, local: UUID, pages: Int) async throws {
        // Bounded twice over. By `pages`, so a round ends while the phone is
        // still answering taps, and by maximumPages, because a loop that
        // depends on the far end agreeing to stop is a loop that hangs the app
        // when it does not.
        for _ in 0..<min(pages, Self.maximumPages) {
            let incoming = try await client.pull(householdID: group, since: cursor, deviceID: deviceID)

            let taken = try await mapper.apply(incoming.records, as: local)
            let removed = try mapper.apply(incoming.deletions)
            lastReceived += taken + removed

            // Nothing moved, so asking again would fetch the same page forever.
            guard incoming.cursor != cursor else { return }
            cursor = incoming.cursor
            guard incoming.hasMore else { return }

            // Applying a page is a long stretch of main actor work and the
            // next one starts the moment this returns. Without this the loop
            // never gives the run loop a turn, the screen stops responding to
            // touches, and iOS can decide the app has hung and kill it, which
            // leaves the cursor where it was and does the whole thing again on
            // the next launch. That is the shape of "it freezes every time".
            await Task.yield()
        }
    }

    /// 500 rows a page, so twenty thousand rows in one sync, which is more
    /// than the whole library and comfortably more than a week of changes.
    static let maximumPages = 40

    /// What an automatic round will take in before leaving the rest for the
    /// next one. Four pages is two thousand records, which is a second or two
    /// of work rather than a minute of frozen screen.
    static let automaticPages = 4

    var cursorDescription: String {
        cursor.isStart ? "nothing yet" : "records \(cursor.records), deletions \(cursor.deletions)"
    }

    /// What a sync would send right now, without sending it.
    func pendingCount() throws -> Int {
        try mapper.records(changedSince: sentUpTo).count
    }

    /// Starts this device over: everything is sent and everything is taken.
    /// For after a restore, or when the two phones have plainly drifted.
    func resetCursor() {
        cursor = SyncCursor()
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
