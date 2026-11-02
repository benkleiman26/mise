import Foundation

/// `SyncClient` over Supabase's PostgREST endpoints.
///
/// Two reads and two writes, which is the whole of it. Everything clever lives
/// in the two SQL functions in `supabase/schema.sql`, where it can be made
/// atomic and where a retry cannot overwrite a newer edit.
struct SupabaseSyncClient: SyncClient {
    let config: SupabaseConfig
    let auth: SupabaseAuth
    let session: URLSession

    init(config: SupabaseConfig, auth: SupabaseAuth, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    /// One page. A household that has been offline for a month still syncs, it
    /// just takes several rounds, and a reply that does not fit in memory is
    /// worse than a second request.
    private static let pageSize = 500

    // MARK: - Pull

    func pull(householdID: UUID, since: Date?, deviceID: UUID) async throws -> SyncBatch {
        let cursor = since.map(Self.iso.string(from:))

        let records: [[String: Any]] = try await get(
            "mise_records",
            query: [
                ("select", "entity,id,fields,updated_at,server_at"),
                ("household_id", "eq.\(householdID.uuidString.lowercased())"),
                // Its own writes come back as its own, which it already has.
                ("device_id", "neq.\(deviceID.uuidString.lowercased())"),
                ("order", "server_at.asc"),
                ("limit", "\(Self.pageSize)"),
            ] + (cursor.map { [("server_at", "gt.\($0)")] } ?? [])
        )

        let deletions: [[String: Any]] = try await get(
            "mise_deletions",
            query: [
                ("select", "entity,record_id,deleted_at,server_at,device_id"),
                ("household_id", "eq.\(householdID.uuidString.lowercased())"),
                ("device_id", "neq.\(deviceID.uuidString.lowercased())"),
                ("order", "server_at.asc"),
                ("limit", "\(Self.pageSize)"),
            ] + (cursor.map { [("server_at", "gt.\($0)")] } ?? [])
        )

        var batch = SyncBatch()
        batch.records = records.compactMap { Self.record(from: $0, householdID: householdID) }
        batch.deletions = deletions.compactMap { Self.deletion(from: $0, householdID: householdID) }

        // The furthest point actually seen, so nothing between the newest row
        // in this page and the server's current clock is skipped.
        let seen = (records + deletions).compactMap { $0["server_at"] as? String }.compactMap(Self.iso.date(from:))
        batch.cursor = seen.max() ?? since
        return batch
    }

    // MARK: - Push

    func push(_ batch: SyncBatch, householdID: UUID, deviceID: UUID) async throws -> Date {
        var serverTime: Date?

        if !batch.records.isEmpty {
            let payload = batch.records.map { record -> [String: Any] in
                [
                    "household_id": householdID.uuidString.lowercased(),
                    "entity": record.entity.rawValue,
                    "id": record.id.uuidString.lowercased(),
                    "fields": Self.json(record.fields),
                    "updated_at": Self.iso.string(from: record.updatedAt),
                    "device_id": deviceID.uuidString.lowercased(),
                ]
            }
            serverTime = try await call("mise_push_records", payload: payload)
        }

        if !batch.deletions.isEmpty {
            let payload = batch.deletions.map { deletion -> [String: Any] in
                [
                    "household_id": householdID.uuidString.lowercased(),
                    "entity": deletion.entity.rawValue,
                    "record_id": deletion.recordID.uuidString.lowercased(),
                    "deleted_at": Self.iso.string(from: deletion.deletedAt),
                    "device_id": deviceID.uuidString.lowercased(),
                ]
            }
            serverTime = try await call("mise_push_deletions", payload: payload) ?? serverTime
        }

        return serverTime ?? Date()
    }

    // MARK: - The wire

    private func get(_ table: String, query: [(String, String)]) async throws -> [[String: Any]] {
        var components = URLComponents(url: config.url.appending(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        try await sign(&request)

        let data = try await send(request)
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func call(_ function: String, payload: [[String: Any]]) async throws -> Date? {
        var request = URLRequest(url: config.url.appending(path: "/rest/v1/rpc/\(function)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await sign(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["payload": payload])

        let data = try await send(request)
        // The function returns a bare timestamptz, which comes back as a JSON
        // string with quotes around it.
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"\n ")) ?? ""
        return Self.iso.date(from: text)
    }

    private func sign(_ request: inout URLRequest) async throws {
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.server(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncError.server("The server gave an answer Mise could not read.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["message"] as? String }
                ?? "The server answered \(http.statusCode)."
            throw SyncError.server(detail)
        }
        return data
    }

    // MARK: - Shapes

    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func record(from row: [String: Any], householdID: UUID) -> SyncRecord? {
        guard let entityName = row["entity"] as? String,
              let entity = SyncEntity(rawValue: entityName),
              let idText = row["id"] as? String, let id = UUID(uuidString: idText),
              let fields = row["fields"] as? [String: Any],
              let updatedText = row["updated_at"] as? String,
              let updatedAt = date(from: updatedText)
        else { return nil }

        return SyncRecord(
            entity: entity,
            id: id,
            householdID: householdID,
            updatedAt: updatedAt,
            fields: fields.mapValues(value(from:))
        )
    }

    private static func deletion(from row: [String: Any], householdID: UUID) -> SyncDeletion? {
        guard let entityName = row["entity"] as? String,
              let entity = SyncEntity(rawValue: entityName),
              let idText = row["record_id"] as? String, let id = UUID(uuidString: idText),
              let deletedText = row["deleted_at"] as? String,
              let deletedAt = date(from: deletedText),
              let deviceText = row["device_id"] as? String, let deviceID = UUID(uuidString: deviceText)
        else { return nil }

        return SyncDeletion(
            entity: entity,
            recordID: id,
            householdID: householdID,
            deletedAt: deletedAt,
            deviceID: deviceID
        )
    }

    /// Postgres returns fractional seconds sometimes and not others, and
    /// `ISO8601DateFormatter` refuses whichever it was not configured for.
    static func date(from text: String) -> Date? {
        if let parsed = iso.date(from: text) { return parsed }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let parsed = plain.date(from: text) { return parsed }
        // Postgres writes "+00" where ISO8601 wants "+00:00" or "Z".
        if text.hasSuffix("+00") { return date(from: String(text.dropLast(3)) + "Z") }
        return nil
    }

    private static func value(from any: Any) -> SyncValue {
        switch any {
        case let value as Bool: .boolean(value)
        case let value as Int: .integer(value)
        case let value as Double: .number(value)
        case let value as [String]: .strings(value)
        case let value as String: .string(value)
        case is NSNull: .null
        default: .null
        }
    }

    private static func json(_ fields: [String: SyncValue]) -> [String: Any] {
        fields.mapValues { value -> Any in
            switch value {
            case .string(let text): text
            case .number(let number): number
            case .integer(let number): number
            case .boolean(let flag): flag
            case .date(let date): iso.string(from: date)
            case .uuid(let id): id.uuidString
            case .strings(let list): list
            case .uuids(let list): list.map(\.uuidString)
            case .null: NSNull()
            }
        }
    }
}
