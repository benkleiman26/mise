import Foundation

/// Signing in, as Supabase's auth API does it.
///
/// Written against the REST endpoints rather than taking their SDK. The whole
/// surface this app needs is three calls, the SDK brings its own concurrency
/// and storage opinions, and a dependency that updates on someone else's
/// schedule is a poor trade for a household app that has to keep working.
actor SupabaseAuth {
    struct Session: Codable, Sendable, Equatable {
        let accessToken: String
        let refreshToken: String
        let userID: UUID
        let expiresAt: Date

        /// Treated as expired a minute early, because a token that dies
        /// mid-request fails the whole sync rather than one call.
        var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
    }

    private let config: SupabaseConfig
    private let session: URLSession
    private var current: Session?

    fileprivate static let storageKey = "supabase.session"

    init(config: SupabaseConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.current = Self.restore()
    }

    var signedInUserID: UUID? { current?.userID }
    var isSignedIn: Bool { current != nil }

    /// When the stored token runs out, for the Details panel. A policy
    /// failure with an expired token here means the refresh is at fault
    /// rather than the policy.
    nonisolated var storedExpiry: Date? {
        guard let text = Keychain.get(Self.storageKey), let data = text.data(using: .utf8) else { return nil }
        return (try? JSONDecoder().decode(Session.self, from: data))?.expiresAt
    }

    // MARK: - The three calls

    func signUp(email: String, password: String) async throws -> Session {
        let session = try await authenticate(path: "/auth/v1/signup", body: [
            "email": email, "password": password,
        ])
        store(session)
        return session
    }

    func signIn(email: String, password: String) async throws -> Session {
        let session = try await authenticate(path: "/auth/v1/token?grant_type=password", body: [
            "email": email, "password": password,
        ])
        store(session)
        return session
    }

    func signOut() {
        current = nil
        Keychain.remove(Self.storageKey)
    }

    /// A token good for the next call, refreshing it if it is about to expire.
    func accessToken() async throws -> String {
        guard let current else { throw SyncError.notSignedIn }
        if current.isFresh { return current.accessToken }

        let refreshed = try await authenticate(path: "/auth/v1/token?grant_type=refresh_token", body: [
            "refresh_token": current.refreshToken,
        ])
        store(refreshed)
        return refreshed.accessToken
    }

    // MARK: - Private

    private func authenticate(path: String, body: [String: String]) async throws -> Session {
        var request = URLRequest(url: config.url.appending(path: path.components(separatedBy: "?")[0]))
        if let query = path.components(separatedBy: "?").dropFirst().first,
           var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
            components.query = query
            request.url = components.url
        }

        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
            throw SyncError.server(Self.message(in: data, status: http.statusCode))
        }

        return try Self.session(from: data)
    }

    /// Supabase puts the useful sentence in one of three fields depending on
    /// which part answered, and the status code alone is not something to show
    /// a person.
    private static func message(in data: Data, status: Int) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "The server answered \(status)."
        }
        for key in ["error_description", "msg", "message", "error"] {
            if let text = object[key] as? String, !text.isEmpty { return text }
        }
        return "The server answered \(status)."
    }

    private static func session(from data: Data) throws -> Session {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String,
              let refresh = object["refresh_token"] as? String,
              let user = object["user"] as? [String: Any],
              let idText = user["id"] as? String,
              let id = UUID(uuidString: idText)
        else {
            // Supabase answers a signup with no session when the project has
            // email confirmation on, which is its default.
            throw SyncError.server("Check your email to confirm the account, then sign in.")
        }

        let seconds = (object["expires_in"] as? Double) ?? 3600
        return Session(
            accessToken: access,
            refreshToken: refresh,
            userID: id,
            expiresAt: Date().addingTimeInterval(seconds)
        )
    }

    private func store(_ session: Session) {
        current = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        Keychain.set(String(data: data, encoding: .utf8), for: Self.storageKey)
    }

    private static func restore() -> Session? {
        guard let text = Keychain.get(storageKey), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }
}
