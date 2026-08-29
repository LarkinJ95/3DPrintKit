import Foundation

/// A short-lived, signed-in-place record of the last resolved entitlement.
///
/// Its only job is to stop a paying customer seeing "Free" for a second on a
/// cold launch, or while offline. It is stored in the Keychain rather than
/// UserDefaults so it cannot be edited with a plist editor, and it expires so a
/// stale device cannot hold Pro indefinitely.
///
/// Expiring the cache never affects the user's data: quotas gate creation only,
/// so an account that drops to Free keeps full access to everything it has.
struct EntitlementSnapshot: Codable, Equatable, Sendable {
    var isPro: Bool
    var isLifetime: Bool
    var isInTrial: Bool
    var expiresAt: Date?
    var kind: String?
    var resolvedAt: Date

    /// How long a cached entitlement is honoured without reaching Apple or the
    /// PrintKit server.
    static let maximumAge: TimeInterval = 14 * 24 * 60 * 60

    var isFresh: Bool {
        // A lifetime purchase has no expiry to go stale against, but it is
        // still re-checked whenever the app can reach StoreKit.
        Date.now.timeIntervalSince(resolvedAt) < Self.maximumAge
    }
}

enum EntitlementCache {
    private static let service = "app.printkit.entitlement"
    private static let account = "snapshot"

    static func load() -> EntitlementSnapshot? {
        guard let data = readData() else { return nil }
        return try? JSONDecoder().decode(EntitlementSnapshot.self, from: data)
    }

    static func save(_ snapshot: EntitlementSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        writeData(data)
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: Keychain

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readData() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func writeData(_ data: Data) {
        SecItemDelete(baseQuery() as CFDictionary)
        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
