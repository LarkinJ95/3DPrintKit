import Foundation

/// The app's single answer to "what may this user do?".
///
/// Every screen asks this object. Nothing else in the app inspects StoreKit,
/// reads a product identifier, or checks `isPro` — see docs/product-plan.md §5.
///
/// It merges two sources:
///   * StoreKit, which knows what this Apple ID bought;
///   * the PrintKit server, which is authoritative for cloud resources.
///
/// The more generous of the two wins, so a fresh purchase works immediately
/// without waiting for a webhook — except that a server-side refund or
/// revocation always wins, so a refunded account cannot keep access by holding
/// a stale local receipt.
@MainActor
@Observable
final class EntitlementService {
    static let shared = EntitlementService()

    // MARK: Published state

    private(set) var isPro = false
    private(set) var isLifetime = false
    private(set) var isInTrial = false
    private(set) var expiresAt: Date?
    private(set) var activeKind: ProductKind?
    /// Set when the server has been reached at least once this launch.
    private(set) var serverState: ServerEntitlement?
    private(set) var lastReconcileFailed = false

    private var observer: NSObjectProtocol?

    private init() {
        applyCachedSnapshot()
        observer = NotificationCenter.default.addObserver(
            forName: .printKitStoreEntitlementChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recomputeFromStore() }
        }
    }

    // No deinit: a process-lifetime singleton, and removing the observer from
    // a deinit would reach main-actor state from a nonisolated context.

    // MARK: The questions the rest of the app asks

    private var entitlementSet: EntitlementSet { EntitlementPolicy.set(isPro: isPro) }

    func can(_ capability: Capability) -> Bool {
        entitlementSet.capabilities.contains(capability)
    }

    func quota(for kind: RecordKind) -> Quota {
        entitlementSet.quota(for: kind)
    }

    /// The creation gate.
    ///
    /// Deliberately the only quota check in the app: quotas gate *creation*
    /// and nothing else. There is no path here — or anywhere — that hides,
    /// archives, or deletes a record because of entitlement state, so a user
    /// over their limit keeps full access to everything they already made.
    func canCreate(_ kind: RecordKind, existing count: Int) -> GateResult {
        switch quota(for: kind) {
        case .unlimited:
            return .allowed
        case .limited(let limit):
            guard count >= limit else { return .allowed }
            return .blocked(.quota(kind, limit: limit, current: count))
        }
    }

    /// Gate a Pro feature by name, so the caller never names a capability.
    func gate(_ feature: FeatureKey) -> GateResult {
        can(feature.capability) ? .allowed : .blocked(.proFeature(feature))
    }

    // MARK: Plan description

    enum PlanDisplay: Equatable {
        case free
        case expired
        case trial(endsAt: Date?)
        case monthly(renewsAt: Date?)
        case annual(renewsAt: Date?)
        case lifetime
    }

    var planDisplay: PlanDisplay {
        if isLifetime { return .lifetime }
        if isInTrial { return .trial(endsAt: expiresAt) }
        if isPro {
            switch activeKind {
            case .annual: return .annual(renewsAt: expiresAt)
            case .monthly: return .monthly(renewsAt: expiresAt)
            default: return .annual(renewsAt: expiresAt)
            }
        }
        if serverState?.status == "expired" || (expiresAt.map { $0 < .now } ?? false) {
            return .expired
        }
        return .free
    }

    var planTitle: String {
        switch planDisplay {
        case .free: return "Free"
        case .expired: return "Free — Pro expired"
        case .trial: return "Pro — Free trial"
        case .monthly: return "3dPrintKit Pro — Monthly"
        case .annual: return "3dPrintKit Pro — Annual"
        case .lifetime: return "3dPrintKit Pro — Lifetime"
        }
    }

    // MARK: Resolution

    /// Full launch sequence: cached snapshot, StoreKit, then the server.
    func refresh() async {
        await PurchaseManager.shared.refreshEntitlements()
        recomputeFromStore()
        await reconcileWithServer()
    }

    private func recomputeFromStore() {
        let store = PurchaseManager.shared.storeState
        apply(store: store, server: serverState)
    }

    /// Send Apple's signed transaction to the server and adopt its answer.
    func reconcileWithServer() async {
        guard APIClient.shared.isConfigured, AuthManager.shared.isSignedIn else { return }

        do {
            if let signed = await PurchaseManager.shared.latestSignedTransaction() {
                let state: ServerEntitlement = try await APIClient.shared.request(
                    "POST", "/api/v1/entitlement/verify",
                    body: VerifyBody(signed_transaction: signed)
                )
                serverState = state
            } else {
                let state: ServerEntitlement = try await APIClient.shared.request(
                    "GET", "/api/v1/entitlement"
                )
                serverState = state
            }
            lastReconcileFailed = false
        } catch {
            // Offline or server trouble: keep whatever StoreKit says. Never
            // downgrade a paying customer because the network is unavailable.
            lastReconcileFailed = true
        }
        apply(store: PurchaseManager.shared.storeState, server: serverState)
    }

    private func apply(store: StoreEntitlement, server: ServerEntitlement?) {
        // A refund or revocation on the server is final, whatever the device holds.
        let serverRevoked = server?.status == "refunded" || server?.status == "revoked"

        let serverPro = (server?.plan == "pro") && !serverRevoked
        let resolvedPro = serverRevoked ? false : (store.isPro || serverPro)

        isPro = resolvedPro
        isLifetime = serverRevoked ? false : (store.isLifetime || (server?.lifetime ?? false))
        isInTrial = store.isInTrial || server?.status == "trial"
        activeKind = store.kind ?? server?.productKind
        expiresAt = isLifetime ? nil : (store.expiresAt ?? server?.expiresDate)

        cacheSnapshot()
    }

    // MARK: Offline cache

    /// Entitlement is cached so a launch without network does not flash Free at
    /// a paying customer. It lives in the Keychain rather than UserDefaults, and
    /// is honoured for a bounded window — after which the app falls back to
    /// Free while, as always, leaving every existing record fully accessible.
    private func applyCachedSnapshot() {
        guard let snapshot = EntitlementCache.load(), snapshot.isFresh else { return }
        isPro = snapshot.isPro
        isLifetime = snapshot.isLifetime
        isInTrial = snapshot.isInTrial
        expiresAt = snapshot.expiresAt
        activeKind = snapshot.kind.flatMap(ProductKind.init(rawValue:))
    }

    private func cacheSnapshot() {
        EntitlementCache.save(
            EntitlementSnapshot(
                isPro: isPro,
                isLifetime: isLifetime,
                isInTrial: isInTrial,
                expiresAt: expiresAt,
                kind: activeKind?.rawValue,
                resolvedAt: .now
            )
        )
    }

    private struct VerifyBody: Encodable {
        let signed_transaction: String
    }
}

/// The server's view, decoded from `GET /api/v1/entitlement`.
struct ServerEntitlement: Decodable, Equatable, Sendable {
    let plan: String
    let status: String
    let source: String?
    let expires_at: String?
    let lifetime: Bool
    let capabilities: [String]
    let last_verified_at: String?

    var expiresDate: Date? {
        guard let expires_at else { return nil }
        return ISO8601DateFormatter.printKit.date(from: expires_at)
    }

    /// Best-effort mapping for display; entitlement itself never depends on it.
    var productKind: ProductKind? {
        lifetime ? .lifetime : nil
    }
}

extension ISO8601DateFormatter {
    static let printKit: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
