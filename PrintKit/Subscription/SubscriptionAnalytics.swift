import Foundation

/// Subscription funnel events.
///
/// Deliberately narrow: an event carries the feature key, the tier, and the
/// product kind — never anything about what the user prints, owns, or plans.
/// Nothing here is transmitted by default; events are appended to a local ring
/// buffer that Settings can display, so the funnel can be studied without
/// building a tracking pipeline first.
enum SubscriptionAnalytics {
    enum Event: Equatable, Sendable {
        case paywallViewed(source: Source)
        case featureAttempted(key: String)
        case quotaLimitReached(kind: RecordKind, limit: Int)
        case trialStarted(kind: ProductKind)
        case purchased(kind: ProductKind)
        case purchaseRestored(kind: ProductKind?)
        case subscriptionExpired(previous: ProductKind?)

        var name: String {
            switch self {
            case .paywallViewed: return "pro_paywall_viewed"
            case .featureAttempted: return "pro_feature_attempted"
            case .quotaLimitReached: return "quota_limit_reached"
            case .trialStarted: return "trial_started"
            case .purchased(let kind):
                switch kind {
                case .monthly: return "monthly_purchased"
                case .annual: return "annual_purchased"
                case .lifetime: return "lifetime_purchased"
                }
            case .purchaseRestored: return "purchase_restored"
            case .subscriptionExpired: return "subscription_expired"
            }
        }

        var properties: [String: String] {
            switch self {
            case .paywallViewed(let source): return ["source": source.rawValue]
            case .featureAttempted(let key): return ["feature_key": key]
            case .quotaLimitReached(let kind, let limit):
                return ["record_kind": kind.rawValue, "limit": String(limit)]
            case .trialStarted(let kind), .purchased(let kind):
                return ["product_kind": kind.rawValue]
            case .purchaseRestored(let kind):
                return ["product_kind": kind?.rawValue ?? "none"]
            case .subscriptionExpired(let previous):
                return ["previous_kind": previous?.rawValue ?? "none"]
            }
        }
    }

    enum Source: String, Sendable {
        case settings, contextual, onboarding, deepLink
    }

    struct Record: Codable, Identifiable, Sendable {
        var id = UUID()
        var name: String
        var properties: [String: String]
        var at: Date
    }

    private static let key = "printkit.subscriptionEvents"
    private static let limit = 200

    static func log(_ event: Event) {
        var records = recent()
        records.append(Record(name: event.name, properties: event.properties, at: .now))
        if records.count > limit { records.removeFirst(records.count - limit) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func recent() -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
