import Foundation

/// One record on the wire, as a bag of fields.
///
/// Deliberately not the SwiftData models. The wire format has to survive one
/// device running an older version of the app than the other, which is the
/// normal state of a household: one phone updates on Tuesday and the other on
/// Friday. A typed struct per table would mean the older phone refusing a
/// record it could have mostly understood, and the newer phone dropping fields
/// the older one sent.
struct SyncRecord: Equatable, Sendable {
    let entity: SyncEntity
    let id: UUID
    let householdID: UUID
    let updatedAt: Date
    /// JSON object, already encoded. Fields a reader does not know are kept and
    /// written back untouched, so a round trip through an older app does not
    /// quietly strip what a newer one wrote.
    let fields: [String: SyncValue]
}

/// A JSON value, with just enough cases for what the models hold.
enum SyncValue: Equatable, Sendable, Codable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case date(Date)
    case uuid(UUID)
    case strings([String])
    case uuids([UUID])
    case null

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let value = try? single.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? single.decode(Int.self) { self = .integer(value); return }
        if let value = try? single.decode(Double.self) { self = .number(value); return }
        if let value = try? single.decode([String].self) { self = .strings(value); return }
        if let value = try? single.decode(String.self) { self = .string(value); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .string(let value): try single.encode(value)
        case .number(let value): try single.encode(value)
        case .integer(let value): try single.encode(value)
        case .boolean(let value): try single.encode(value)
        case .date(let value): try single.encode(ISO8601DateFormatter().string(from: value))
        case .uuid(let value): try single.encode(value.uuidString)
        case .strings(let value): try single.encode(value)
        case .uuids(let value): try single.encode(value.map(\.uuidString))
        case .null: try single.encodeNil()
        }
    }
}

/// What a device sends up and what it gets back.
struct SyncBatch: Equatable, Sendable {
    var records: [SyncRecord] = []
    var deletions: [SyncDeletion] = []
    /// The server's clock at the moment this batch was taken, which is what
    /// the device stores and sends next time. Device clocks disagree, sometimes
    /// by minutes, and a cursor taken from the wrong clock loses changes.
    var cursor: Date?
}

struct SyncDeletion: Equatable, Sendable {
    let entity: SyncEntity
    let recordID: UUID
    let householdID: UUID
    let deletedAt: Date
    let deviceID: UUID
}

/// The server, as the engine needs it. One protocol so the engine can be
/// tested against an in-memory stand-in, and so Supabase is an implementation
/// detail rather than a dependency of everything.
protocol SyncClient: Sendable {
    /// Everything in the household changed after `since`, excluding what this
    /// device sent itself.
    func pull(householdID: UUID, since: Date?, deviceID: UUID) async throws -> SyncBatch

    /// Sends local changes. Returns the server's clock, which becomes the next
    /// cursor.
    func push(_ batch: SyncBatch, householdID: UUID, deviceID: UUID) async throws -> Date
}

enum SyncError: LocalizedError {
    case notSignedIn
    case notSharing
    case noHousehold
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in to share this household."
        case .notSharing: "Start sharing, or join with an invite code, before syncing."
        case .noHousehold: "Mise has not finished setting up. Close the app and open it again."
        case .server(let detail): "Mise could not reach the server. \(detail)"
        }
    }
}
