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

    /// What the last round did, for a line the user can read.
    private(set) var lastSummary: String?

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
        step = await auth.isSignedIn ? .ready : .signedOut
    }

    // MARK: - Account

    func signIn(email: String, password: String) async {
        await attempt { try await $0.signIn(email: email, password: password) }
        signedInEmail = step == .ready ? email : nil
    }

    func signUp(email: String, password: String) async {
        await attempt { try await $0.signUp(email: email, password: password) }
        signedInEmail = step == .ready ? email : nil
    }

    func signOut() async {
        await auth?.signOut()
        signedInEmail = nil
        step = .signedOut
        // The sharing group stays. Signing back in should not mean setting
        // sharing up again.
    }

    private func attempt(_ work: @escaping (SupabaseAuth) async throws -> SupabaseAuth.Session) async {
        guard let auth else { return }
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
    func startSharing() async { await enterGroup(SyncGroup.makeIfNeeded()) }

    func joinSharing(code: String) async {
        guard let id = SyncGroup.join(code: code) else {
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
        guard let config, let auth else { return }
        busy = true
        defer { busy = false }

        do {
            guard let userID = await auth.signedInUserID else { throw SyncError.notSignedIn }

            var request = URLRequest(url: config.url.appending(path: "/rest/v1/mise_household_members"))
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Joining twice is something people do, and it should be quiet.
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

            problem = nil
            await sync()
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: - Syncing

    func sync() async {
        guard let engine, step == .ready, isSharing else { return }
        busy = true
        defer { busy = false }

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

    private static func summary(sent: Int, received: Int) -> String {
        switch (sent, received) {
        case (0, 0): "Already up to date"
        case (let out, 0): "Sent \(out)"
        case (0, let inbound): "Received \(inbound)"
        case (let out, let inbound): "Sent \(out), received \(inbound)"
        }
    }
}
