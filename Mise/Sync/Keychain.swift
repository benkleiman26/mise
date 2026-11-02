import Foundation
import Security

/// Somewhere to keep the session that is not `UserDefaults`.
///
/// A refresh token is a long lived credential to the household's data.
/// `UserDefaults` is a plist in the app container: readable from a backup, and
/// from anything with access to the file system on a jailbroken device. The
/// Keychain is encrypted and tied to this device.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` rather than the default:
/// sync wants to run in the background, so the token has to be readable while
/// the phone is locked, and it should never travel in an iCloud backup to a
/// device that was never signed in.
enum Keychain {
    static func set(_ value: String?, for key: String) {
        guard let value, let data = value.data(using: .utf8) else {
            remove(key)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.benkleiman.mise",
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { current, _ in current } as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.benkleiman.mise",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.benkleiman.mise",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
