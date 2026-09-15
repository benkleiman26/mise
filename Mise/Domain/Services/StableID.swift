import CryptoKit
import Foundation

/// Deterministic identifiers for anything that ships with the app.
///
/// The seed loader runs on every launch and, in the simulator, many times a day.
/// It needs to be able to ask "is this already here" without a side table, so
/// every seeded record derives its id from a stable key instead of being handed
/// a random one. Re-running the seed then produces the same ids and inserts
/// nothing.
///
/// The same property pays off again in Phase 5: two devices in one household
/// that seed independently before they ever sync produce identical rows rather
/// than 297 duplicates.
///
/// These are RFC 4122 version 5 UUIDs, which is the standard way to do this, so
/// any other language can reproduce them. `StableIDTests` checks the
/// implementation against the published test vector.
enum StableID {
    /// Version 5 of the DNS namespace with the name "mise.benkleiman.com".
    /// Written out rather than computed so it is obvious that it never moves.
    static let namespace = UUID(uuidString: "D1F1397F-69B6-5FA9-AB4F-E180C81C0FE1")!

    static func canonicalItem(name: String) -> UUID {
        uuid(name: "canonicalItem:\(name)")
    }

    static func recipe(seedID: String) -> UUID {
        uuid(name: "recipe:\(seedID)")
    }

    static func ingredient(recipeSeedID: String, position: Int) -> UUID {
        uuid(name: "ingredient:\(recipeSeedID):\(position)")
    }

    static func step(recipeSeedID: String, position: Int) -> UUID {
        uuid(name: "step:\(recipeSeedID):\(position)")
    }

    /// v1 has exactly one household, and this is its id.
    static func household(key: String = "default") -> UUID {
        uuid(name: "household:\(key)")
    }

    static func pantryEntry(householdID: UUID, canonicalItemID: UUID) -> UUID {
        uuid(name: "pantryEntry:\(householdID.uuidString):\(canonicalItemID.uuidString)")
    }

    static func user(key: String) -> UUID {
        uuid(name: "user:\(key)")
    }

    static func preferences(householdID: UUID) -> UUID {
        uuid(name: "preferences:\(householdID.uuidString)")
    }

    static func uuid(name: String) -> UUID {
        uuid(namespace: namespace, name: name)
    }

    /// RFC 4122 section 4.3: SHA-1 over the namespace bytes followed by the
    /// name, with the version and variant bits overwritten in the digest.
    static func uuid(namespace: UUID, name: String) -> UUID {
        var input = Data()
        withUnsafeBytes(of: namespace.uuid) { input.append(contentsOf: $0) }
        input.append(contentsOf: Array(name.utf8))

        var digest = Array(Insecure.SHA1.hash(data: input))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80

        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
