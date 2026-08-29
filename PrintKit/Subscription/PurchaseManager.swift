import Foundation
import StoreKit

/// StoreKit 2 owner: loading products, purchasing, restoring, and keeping the
/// device's view of Apple's entitlements current.
///
/// It answers "what has Apple granted this Apple ID?" and nothing else. What
/// that means for the app is `EntitlementService`'s job, and what it means for
/// cloud resources is the server's.
///
/// Modern API only — no `SKPaymentQueue`, no receipt-file parsing.
@MainActor
@Observable
final class PurchaseManager {
    static let shared = PurchaseManager()

    // MARK: State

    private(set) var products: [ProductKind: Product] = [:]
    private(set) var storeState: StoreEntitlement = .none
    private(set) var isLoadingProducts = false
    private(set) var productLoadFailed = false
    /// True while a purchase or restore is in flight.
    private(set) var isWorking = false

    /// Whether this Apple ID may still use the annual introductory offer.
    /// Asked, never assumed: a returning subscriber must not be shown a trial.
    private(set) var isEligibleForTrial = false

    private var updatesTask: Task<Void, Never>?

    private init() {}

    // MARK: Lifecycle

    /// Begin observing transactions. Must run at launch, before any purchase
    /// can start, and must live for the whole process — otherwise Ask to Buy
    /// approvals and renewals that happen outside the app are missed.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let transaction = Self.checkVerified(update) {
                    await self.handle(transaction: transaction)
                }
            }
        }
        Task { await refreshEntitlements() }
    }

    // No deinit: this singleton lives for the life of the process, and the
    // updates listener must outlive every screen that might start a purchase.

    // MARK: Products

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: ProductCatalog.purchasableIdentifiers)
            var mapped: [ProductKind: Product] = [:]
            for product in loaded {
                if let kind = ProductCatalog.kind(for: product.id) { mapped[kind] = product }
            }
            products = mapped
            productLoadFailed = mapped.isEmpty
            await refreshTrialEligibility()
        } catch {
            productLoadFailed = true
        }
    }

    private func refreshTrialEligibility() async {
        guard let annual = products[.annual], let subscription = annual.subscription else {
            isEligibleForTrial = false
            return
        }
        guard subscription.introductoryOffer != nil else {
            isEligibleForTrial = false
            return
        }
        isEligibleForTrial = await subscription.isEligibleForIntroOffer
    }

    /// The trial period Apple actually advertises for the annual product, so
    /// the paywall never states a duration the store would contradict.
    var trialDescription: String? {
        guard isEligibleForTrial,
              let offer = products[.annual]?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let unit: String
        switch offer.period.unit {
        case .day: unit = offer.period.value == 1 ? "day" : "days"
        case .week: unit = offer.period.value == 1 ? "week" : "weeks"
        case .month: unit = offer.period.value == 1 ? "month" : "months"
        case .year: unit = offer.period.value == 1 ? "year" : "years"
        @unknown default: unit = "days"
        }
        return "\(offer.period.value)-\(unit) free trial"
    }

    // MARK: Purchase

    enum PurchaseOutcome: Sendable {
        case success(ProductKind)
        case pending          // Ask to Buy, or SCA — resolved later via updates
        case cancelled
        case unavailable
    }

    /// Purchase, attaching `appAccountToken` so App Store Server Notifications
    /// can be mapped back to this PrintKit account without trusting the client.
    func purchase(_ kind: ProductKind, appAccountToken: UUID?) async throws -> PurchaseOutcome {
        guard let product = products[kind] else { return .unavailable }
        isWorking = true
        defer { isWorking = false }

        var options: Set<Product.PurchaseOption> = []
        if let appAccountToken { options.insert(.appAccountToken(appAccountToken)) }

        let result = try await product.purchase(options: options)
        switch result {
        case .success(let verification):
            guard let transaction = Self.checkVerified(verification) else { return .unavailable }
            await handle(transaction: transaction)
            await transaction.finish()
            return .success(kind)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .unavailable
        }
    }

    /// Explicit Restore Purchases. `AppStore.sync()` prompts for the Apple ID,
    /// so it belongs behind a user action and never runs at launch.
    func restore() async throws {
        isWorking = true
        defer { isWorking = false }
        try await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: Entitlement resolution

    /// Resolve from `Transaction.currentEntitlements` — the authority on this
    /// device. A purchase callback is only a hint that this should re-run.
    func refreshEntitlements() async {
        var resolved: StoreEntitlement = .none

        for await result in Transaction.currentEntitlements {
            guard let transaction = Self.checkVerified(result) else { continue }
            guard let kind = ProductCatalog.kind(for: transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }

            if kind == .lifetime {
                // Permanent, and outranks any subscription state.
                resolved = StoreEntitlement(
                    kind: .lifetime,
                    expiresAt: nil,
                    isInTrial: false,
                    originalTransactionID: String(transaction.originalID),
                    signedTransaction: nil
                )
                break
            }

            if let expiry = transaction.expirationDate, expiry > .now {
                let inTrial = transaction.offerType == .introductory
                resolved = StoreEntitlement(
                    kind: kind,
                    expiresAt: expiry,
                    isInTrial: inTrial,
                    originalTransactionID: String(transaction.originalID),
                    signedTransaction: nil
                )
            }
        }

        // Billing trouble is not a downgrade: honour whatever window Apple
        // still considers entitled (grace period included).
        storeState = resolved
        await refreshTrialEligibility()
        NotificationCenter.default.post(name: .printKitStoreEntitlementChanged, object: nil)
    }

    /// The most recent signed transaction, for server-side verification.
    /// The app never tells the server what it owns — it forwards what Apple signed.
    func latestSignedTransaction() async -> String? {
        var newest: (date: Date, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProductCatalog.kind(for: transaction.productID) != nil else { continue }
            let jws = result.jwsRepresentation
            if newest == nil || transaction.purchaseDate > newest!.date {
                newest = (transaction.purchaseDate, jws)
            }
        }
        return newest?.jws
    }

    // MARK: Private

    private func handle(transaction: Transaction) async {
        await refreshEntitlements()
        await transaction.finish()
    }

    /// Unwrap Apple's verification. An unverified result grants nothing.
    ///
    /// `nonisolated` because it reads only its argument and touches no state:
    /// the `Transaction.updates` listener runs detached from the main actor and
    /// has to call this before it can hop back.
    private nonisolated static func checkVerified(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let transaction): return transaction
        case .unverified: return nil
        }
    }
}

/// What StoreKit says this Apple ID currently owns.
struct StoreEntitlement: Equatable, Sendable {
    var kind: ProductKind?
    var expiresAt: Date?
    var isInTrial: Bool
    var originalTransactionID: String?
    var signedTransaction: String?

    static let none = StoreEntitlement(
        kind: nil, expiresAt: nil, isInTrial: false,
        originalTransactionID: nil, signedTransaction: nil
    )

    var isPro: Bool {
        guard let kind else { return false }
        if kind == .lifetime { return true }
        guard let expiresAt else { return false }
        return expiresAt > .now
    }

    var isLifetime: Bool { kind == .lifetime }
}

extension Notification.Name {
    static let printKitStoreEntitlementChanged = Notification.Name("printkit.storeEntitlementChanged")
}
