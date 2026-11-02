import Foundation

/// This install's own id.
///
/// Sync needs to tell "someone else changed this" from "I changed this", and
/// the one thing a device always knows is which changes are its own. Kept in
/// `UserDefaults` rather than derived from the hardware, because
/// `identifierForVendor` changes when the last app from a vendor is deleted
/// and a device whose id moves under it looks like a second device with the
/// same data.
enum DeviceIdentity {
    private static let key = "mise.device.id"

    static var current: UUID {
        if let saved = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: saved) {
            return id
        }
        let fresh = UUID()
        UserDefaults.standard.set(fresh.uuidString, forKey: key)
        return fresh
    }
}
