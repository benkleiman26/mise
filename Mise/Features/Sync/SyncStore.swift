import Foundation
import SwiftData

/// Sharing a household, as the Settings screen sees it.
///
/// Holds the account, the sharing group and the engine, and keeps the three in
/// step: signing out leaves the group alone, because signing back in should
/// not mean setting sharing up again, and leaving the group resets the engine,
/// because what it has seen is no longer about this household.
@MainActor
@Observable
final class SyncStore {
    enum Step: Equatable {
        /// No `supabase.json` in the bundle.
        case notConfigured
        case signedOut
        case ready
    }

    private let config: SupabaseConfig?
    private let auth: SupabaseAuth?
    private let engine: SyncEngine?

    private(set) var step: Step = .notConfigured
    private(set) var problem: String?
    private(set) var busy = false
    private(set) var signedInEmail: String?
    /// The account id the server will see as `auth.uid()`. Shown in Details
    /// because a policy failure on `user_id = auth.uid()` is either this not
    /// matching the stored row, or the token not being accepted at all, and
    /// those look identical from outside.
    private(set) var signedInUserID: String?

    /// What the last round did, for a line the user can read.
    private(set) var lastSummary: String?
    /// What the server says about who is calling. The one fact that separates
    /// "this account is not a member" from "the server does not think anyone
    /// is calling at all".
    private(set) var serverSays: String?

    init(container: AppContainer) {
        self.config = SupabaseConfig.load()

        guard let config else {
            self.auth = nil
            self.engine = nil
            return
        }

        let auth = SupabaseAuth(config: config)
        self.auth = auth
        self.engine = SyncEngine(
            client: SupabaseSyncClient(config: config, auth: auth),
            mapper: SyncMapper(
                households: container.households,
                users: container.users,
                pantry: container.pantry,
                plans: container.mealPlans,
                lists: container.groceryLists
            ),
            households: container.households,
            context: container.syncContext
        )
    }

    var inviteCode: String? { SyncGroup.current?.uuidString }
    var isSharing: Bool { SyncGroup.current != nil }
    var lastSyncedAt: Date? { engine?.lastSyncedAt }

    var statusText: String {
        switch engine?.status {
        case .working: "Syncing"
        case .failed(let message): message
        default:
            if let summary = lastSummary { summary }
            else if let at = lastSyncedAt {
                "Last synced \(RelativeDateTimeFormatter().localizedString(for: at, relativeTo: .now))"
            } else { "Not synced yet" }
        }
    }

    func load() async {
        guard let auth else {
            step = .notConfigured
            return
        }
        signedInUserID = await auth.signedInUserID?.uuidString
        step = await auth.isSignedIn ? .ready : .signedOut
    }

    // MARK: - Account

    func signIn(email: String, password: String) async {
        await attempt { try await $0.signIn(email: email, password: password) }
        signedInEmail = step == .ready ? email : nil
        signedInUserID = await auth?.signedInUserID?.uuidString
    }

    func signUp(email: String, password: String) async {
        await attempt { try await $0.signUp(email: email, password: password) }
        signedInEmail = step == .ready ? email : nil
        signedInUserID = await auth?.signedInUserID?.uuidString
    }

    func signOut() async {
        await auth?.signOut()
        signedInEmail = nil
        signedInUserID = nil
        step = .signedOut
        // The sharing group stays. Signing back in should not mean setting
        // sharing up again.
    }

    private func attempt(_ work: @escaping (SupabaseAuth) async throws -> SupabaseAuth.Session) async {
        guard let auth else { return }
        problem = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await work(auth)
            problem = nil
            step = .ready
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            step = .signedOut
        }
    }

    // MARK: - The household

    /// Starts sharing, or joins what the other phone started.
    func startSharing() async { await enterGroup(SyncGroup.proposed()) }

    func joinSharing(code: String) async {
        guard let id = SyncGroup.proposed(code: code) else {
            problem = "That invite code does not look right. It should be a long string of letters, numbers and dashes."
            return
        }
        await enterGroup(id)
    }

    func stopSharing() {
        SyncGroup.leave()
        // What the engine has seen is no longer about this household, so the
        // next sync after joining another one starts from the beginning.
        engine?.resetCursor()
        lastSummary = nil
    }

    private func enterGroup(_ id: UUID) async {
        problem = nil
        busy = true
        defer { busy = false }

        do {
            try await register(id)
            // Only now, with the server agreeing this device is a member.
            SyncGroup.adopt(id)
            problem = nil
            await sync()
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Asks the server who it thinks is calling.
    ///
    /// A policy failure on `user_id = auth.uid()` while the app believes it is
    /// signed in means either the stored row belongs to another account or the
    /// token is not being accepted. This says which, in one tap, instead of
    /// another round of reasoning from a status line.
    func checkConnection() async {
        serverSays = nil
        problem = nil

        guard let config, let auth else {
            serverSays = "No server configured."
            return
        }
        busy = true
        defer { busy = false }

        do {
            var request = URLRequest(url: config.url.appending(path: "/rest/v1/rpc/mise_whoami"))
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"\n ")) ?? ""

            if status == 404 {
                serverSays = "The mise_whoami function is missing. Run supabase/schema.sql again."
            } else if !(200..<300).contains(status) {
                serverSays = "HTTP \(status): \(body)"
            } else if body.isEmpty || body == "null" {
                serverSays = "The server sees nobody signed in. The token is being ignored, which is why every policy refuses the write."
            } else if body.lowercased() == signedInUserID?.lowercased() {
                serverSays = "The server sees you, and it is the right account."
            } else {
                serverSays = "The server sees a different account: \(body)"
            }
        } catch {
            serverSays = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Writes the membership row, quietly, every time.
    ///
    /// It is one small idempotent insert, and it is the difference between a
    /// device that recovers on the next tap and one that is stuck forever
    /// showing a row level security error it cannot act on. Devices restored
    /// from a backup arrive in exactly that state: the group is in the
    /// Keychain and the membership is not on the server.
    private func register(_ id: UUID) async throws {
        guard let config, let auth else { throw SyncError.notSignedIn }
        guard let userID = await auth.signedInUserID else { throw SyncError.notSignedIn }

        var request = URLRequest(url: config.url.appending(path: "/rest/v1/mise_household_members"))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "household_id": id.uuidString.lowercased(),
            "user_id": userID.uuidString.lowercased(),
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["message"] as? String } ?? "The server answered \(http.statusCode)."
            throw SyncError.server(detail)
        }
    }

    // MARK: - Syncing

    func sync() async {
        problem = nil
        serverSays = nil

        guard let engine else {
            problem = "Sharing is not set up on this phone: supabase.json is missing from the app bundle."
            return
        }
        guard step == .ready else {
            problem = "Not signed in yet."
            return
        }
        guard let group = SyncGroup.current else {
            problem = "This phone is not in a household yet. Start sharing, or join with an invite code."
            return
        }

        busy = true
        defer { busy = false }

        // Cheap, idempotent, and it rescues a device whose membership never
        // got written: without it, such a phone shows a row level security
        // error forever with no way out but reinstalling.
        do {
            try await register(group)
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }

        await engine.run()

        switch engine.status {
        case .failed(let message):
            problem = message
            lastSummary = nil
        default:
            problem = nil
            lastSummary = Self.summary(sent: engine.lastSent, received: engine.lastReceived)
        }
    }

    /// Plain facts about what sync thinks is true, for when the status line is
    /// not enough. Written because three wrong guesses were made from
    /// "Not synced yet", which is the least informative thing the app could
    /// have said.
    var details: [(String, String)] {
        var out: [(String, String)] = []
        out.append(("Server", config?.url.host() ?? "not configured"))
        out.append(("Engine", engine == nil ? "not built" : "ready"))
        out.append(("Step", "\(step)"))
        out.append(("Household", SyncGroup.current?.uuidString.prefix(8).description ?? "none"))
        out.append(("Device", DeviceIdentity.current.uuidString.prefix(8).description))
        out.append(("Account", signedInUserID ?? "not signed in"))
        out.append(("Token", tokenState))
        out.append(("Engine status", engine.map { "\($0.status)" } ?? "none"))
        out.append(("Seen up to", engine?.cursorDescription ?? "nothing yet"))
        out.append(("Last sent", "\(engine?.lastSent ?? 0)"))
        out.append(("Last received", "\(engine?.lastReceived ?? 0)"))
        out.append(("Changes waiting", "\(pendingCount)"))
        return out
    }

    /// Whether the saved session still looks usable, without calling out.
    /// "Expired" here with a policy failure means the refresh is the problem,
    /// not the policy.
    private var tokenState: String {
        guard let auth else { return "none" }
        return auth.storedExpiry.map { expiry in
            expiry.timeIntervalSinceNow > 60
                ? "good for \(Int(expiry.timeIntervalSinceNow / 60)) min"
                : "expired"
        } ?? "none"
    }

    /// How many local records sync would send right now. Zero here with an
    /// empty server is the whole answer to "why did nothing happen".
    private var pendingCount: Int {
        (try? engine?.pendingCount()) ?? 0
    }

    private static func summary(sent: Int, received: Int) -> String {
        switch (sent, received) {
        case (0, 0): "Already up to date"
        case (let out, 0): "Sent \(out)"
        case (0, let inbound): "Received \(inbound)"
        case (let out, let inbound): "Sent \(out), received \(inbound)"
        }
    }
}
