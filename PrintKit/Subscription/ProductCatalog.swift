import Foundation

/// App Store products, as configuration.
///
/// Nothing in the app branches on a display name or a price. Code reasons about
/// `ProductKind`; the identifiers below are the only place the App Store's
/// vocabulary appears, and prices always come from StoreKit at runtime.
enum ProductKind: String, CaseIterable, Sendable {
    case monthly
    case annual
    case lifetime

    var isSubscription: Bool { self != .lifetime }

    var shortName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        case .lifetime: return "Founder's Lifetime"
        }
    }
}

enum ProductCatalog {
    static let identifiers: [ProductKind: String] = [
        .monthly: "com.3dprintkit.pro.monthly",
        .annual: "com.3dprintkit.pro.annual",
        .lifetime: "com.3dprintkit.pro.lifetime"
    ]

    /// Products offered to new purchasers, in paywall order — annual first, as
    /// the best value. This is the single list: what is sold and how it is
    /// presented are the same decision.
    ///
    /// Retiring the Founder's Lifetime offer means removing `.lifetime` here
    /// and taking the product off sale in App Store Connect. Existing owners
    /// are unaffected: their entitlement comes from
    /// `Transaction.currentEntitlements`, which is resolved from
    /// `allIdentifiers`, not from this list.
    static let availableForPurchase: [ProductKind] = [.annual, .monthly, .lifetime]

    static var allIdentifiers: Set<String> { Set(identifiers.values) }

    static var purchasableIdentifiers: [String] {
        availableForPurchase.compactMap { identifiers[$0] }
    }

    static func kind(for identifier: String) -> ProductKind? {
        identifiers.first(where: { $0.value == identifier })?.key
    }
}
