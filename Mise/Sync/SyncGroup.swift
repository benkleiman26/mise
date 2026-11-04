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

    /// A group id to try, without committing to it.
    ///
    /// Saving before the server has accepted the membership is what made the
    /// first real attempt unrecoverable: the device looked like it was
    /// sharing, the screen offered "Sync now", and every sync was refused
    /// because no membership row had ever been written. Nothing is stored
    /// until `adopt` is called.
    static func proposed() -> UUID { current ?? UUID() }

    /// An invite code, if it is one.
    static func proposed(code: String) -> UUID? { UUID(uuidString: tidy(code)) }

    /// Remembers the group, once the server has agreed this device is in it.
    static func adopt(_ id: UUID) {
        Keychain.set(id.uuidString, for: key)
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
