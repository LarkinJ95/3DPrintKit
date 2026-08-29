import Foundation

extension AuthManager {
    /// The UUID attached to every StoreKit purchase as `appAccountToken`.
    ///
    /// It lets App Store Server Notifications find the right PrintKit account
    /// without the client ever asserting who it is. When the user is signed in
    /// this is their server account id; otherwise it is a stable device-local
    /// UUID, so a purchase made before signing in can still be attached to the
    /// account afterwards.
    var appAccountToken: UUID? {
        if let accountID = KeychainService.read(.accountID), let uuid = UUID(uuidString: accountID) {
            return uuid
        }
        return Self.deviceAppAccountToken
    }

    private static var deviceAppAccountToken: UUID {
        let key = "printkit.appAccountToken"
        if let existing = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: existing) {
            return uuid
        }
        let created = UUID()
        UserDefaults.standard.set(created.uuidString, forKey: key)
        return created
    }
}
