import Foundation

/// The id the server partitions this household's records by.
///
/// Deliberately not `StableID.household()`. That one is derived from a
/// constant string, so every install of Mise on earth has the same local
/// household id. Locally that is harmless and convenient. On a shared server
/// it is a hole: the join policy lets any signed in person add themselves to a
/// household, and a household id that everyone can work out is not a secret.
///
/// So the sharing group gets a random id, made once by whoever sets sync up
/// first and given to the other person as an invite code. A random v4 uuid is
/// not guessable, which makes knowing the code the thing that grants access,
/// the same way a share link works.
///
/// Kept in the Keychain rather than `UserDefaults`, because it is the one
/// piece of information that decides whose groceries this device can read.
enum SyncGroup {
    private static let key = "mise.sync.group"

    static var current: UUID? {
        guard let saved = Keychain.get(key) else { return nil }
        return UUID(uuidString: saved)
    }

    /// The group this device already belongs to, or a new one.
    @discardableResult
    static func makeIfNeeded() -> UUID {
        if let existing = current { return existing }
        let fresh = UUID()
        Keychain.set(fresh.uuidString, for: key)
        return fresh
    }

    /// Joins the group behind an invite code.
    static func join(code: String) -> UUID? {
        guard let id = UUID(uuidString: Self.tidy(code)) else { return nil }
        Keychain.set(id.uuidString, for: key)
        return id
    }

    static func leave() {
        Keychain.remove(key)
    }

    /// People retype these out of a message, so the obvious mangling is
    /// undone rather than refused: spaces, lowercase, and the surrounding
    /// quotes a messaging app adds.
    static func tidy(_ code: String) -> String {
        code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }
}
