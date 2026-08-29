import SwiftUI
import StoreKit

/// The full Pro paywall.
///
/// Calm and typographic, in the app's own visual language. No countdown, no
/// urgency, no "% OFF", no pre-selected upsell — the annual plan is emphasised
/// because it is the best value, and that is the only emphasis on the screen.
///
/// Prices and trial terms are read from StoreKit, never hard-coded, so App
/// Store Connect changes and every storefront's localized pricing appear here
/// without a release.
struct PaywallView: View {
    var source: SubscriptionAnalytics.Source = .settings

    @Environment(\.dismiss) private var dismiss
    @State private var purchases = PurchaseManager.shared
    @State private var entitlements = EntitlementService.shared
    @State private var selection: ProductKind = .annual
    @State private var errorMessage: String?
    @State private var showThanks = false

    private let benefits: [(String, String)] = [
        ("infinity", "Unlimited spools & printers"),
        ("wave.3.right", "NFC spool tagging"),
        ("icloud", "Cloud backup & sync"),
        ("desktopcomputer", "3dPrintKit Desktop"),
        ("checkmark.seal", "Print Readiness"),
        ("shippingbox", "Projects & print history"),
        ("wrench.and.screwdriver", "Maintenance & drying"),
        ("chart.xyaxis.line", "Advanced analytics"),
        ("brain", "Personal printing knowledge")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PK.Spacing.xl) {
                    header
                    benefitList
                    planOptions
                    actions
                    legal
                }
                .padding(PK.Spacing.lg)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await purchases.loadProducts()
                // A product can be missing in a storefront where it was never
                // made available. Land on something purchasable rather than
                // showing a disabled button with no explanation.
                if purchases.products[selection] == nil,
                   let fallback = ProductCatalog.availableForPurchase.first(where: { purchases.products[$0] != nil }) {
                    selection = fallback
                }
                SubscriptionAnalytics.log(.paywallViewed(source: source))
            }
            .alert("Purchase problem", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("You're all set", isPresented: $showThanks) {
                Button("Done") { dismiss() }
            } message: {
                Text("3dPrintKit Pro is active on this Apple ID.")
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: PK.Spacing.sm) {
            Text("3dPrintKit Pro")
                .font(.largeTitle.weight(.bold))
            Text("Your complete 3D printing toolkit, everywhere.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: PK.Spacing.sm) {
            ForEach(benefits, id: \.1) { symbol, text in
                Label {
                    Text(text).font(.subheadline)
                } icon: {
                    Image(systemName: symbol)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                }
            }
        }
    }

    @ViewBuilder
    private var planOptions: some View {
        if purchases.isLoadingProducts && purchases.products.isEmpty {
            HStack {
                ProgressView()
                Text("Loading plans…").font(.subheadline).foregroundStyle(.secondary)
            }
        } else if purchases.productLoadFailed {
            PKCallout(
                status: .warning,
                message: "Plans couldn't be loaded from the App Store. Check your connection and try again."
            )
        } else {
            VStack(spacing: PK.Spacing.sm) {
                ForEach(ProductCatalog.availableForPurchase, id: \.self) { kind in
                    if let product = purchases.products[kind] {
                        planRow(kind: kind, product: product)
                    }
                }
            }
        }
    }

    private func planRow(kind: ProductKind, product: Product) -> some View {
        Button {
            selection = kind
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.shortName).font(.headline)
                    if kind == .annual {
                        // Only ever advertise a trial Apple will actually honour.
                        Text(bestValueLine)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    } else if kind == .lifetime {
                        Text("One-time purchase · early adopter offer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: PK.Spacing.md)
                Text(product.displayPrice)
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(PK.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: PK.Radius.card)
                    .fill(selection == kind ? Color.accentColor.opacity(0.10) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PK.Radius.card)
                    .strokeBorder(selection == kind ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == kind ? [.isSelected] : [])
    }

    private var bestValueLine: String {
        if let trial = purchases.trialDescription {
            return "Best value · \(trial)"
        }
        return "Best value"
    }

    private var primaryTitle: String {
        if selection == .annual, let trial = purchases.trialDescription {
            return "Start \(trial.replacingOccurrences(of: " free trial", with: "")) Free Trial"
        }
        switch selection {
        case .annual: return "Subscribe Annually"
        case .monthly: return "Subscribe Monthly"
        case .lifetime: return "Get Founder's Lifetime"
        }
    }

    private var actions: some View {
        VStack(spacing: PK.Spacing.sm) {
            Button {
                Task { await buy(selection) }
            } label: {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(purchases.isWorking || purchases.products[selection] == nil)

            Button("Restore Purchases") {
                Task { await restore() }
            }
            .font(.subheadline)
            .disabled(purchases.isWorking)
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: PK.Spacing.sm) {
            Text(subscriptionTerms)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: PK.Spacing.lg) {
                Link("Privacy Policy", destination: URL(string: "https://3dprintkit.app/privacy")!)
                Link("Terms of Use", destination: URL(string: "https://3dprintkit.app/terms")!)
            }
            .font(.caption2)
        }
    }

    /// Required disclosure: length, price, renewal, and how to cancel — on the
    /// paywall itself, not behind a link.
    private var subscriptionTerms: String {
        let annual = purchases.products[.annual]?.displayPrice ?? "the annual price"
        let monthly = purchases.products[.monthly]?.displayPrice ?? "the monthly price"
        let trialSentence = purchases.trialDescription.map {
            "The annual plan begins with a \($0); you are not charged until it ends. "
        } ?? ""
        return """
        \(trialSentence)Annual (\(annual)) and Monthly (\(monthly)) are auto-renewing \
        subscriptions. Payment is charged to your Apple Account at confirmation of purchase, \
        and renews automatically for the same period unless you cancel at least 24 hours before \
        the current period ends. Manage or cancel in Settings › Apple Account › Subscriptions. \
        Founder's Lifetime is a one-time purchase and does not renew.
        """
    }

    // MARK: Actions

    private func buy(_ kind: ProductKind) async {
        do {
            let outcome = try await purchases.purchase(kind, appAccountToken: AuthManager.shared.appAccountToken)
            switch outcome {
            case .success(let purchased):
                if purchased == .annual, purchases.isEligibleForTrial {
                    SubscriptionAnalytics.log(.trialStarted(kind: purchased))
                }
                SubscriptionAnalytics.log(.purchased(kind: purchased))
                await entitlements.refresh()
                showThanks = true
            case .pending:
                errorMessage = "This purchase needs approval before it can finish. You'll get access as soon as it's approved."
            case .cancelled:
                break
            case .unavailable:
                errorMessage = "That plan isn't available right now. Please try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        do {
            try await purchases.restore()
            await entitlements.refresh()
            SubscriptionAnalytics.log(.purchaseRestored(kind: entitlements.activeKind))
            if entitlements.isPro {
                showThanks = true
            } else {
                errorMessage = "No previous 3dPrintKit Pro purchase was found on this Apple ID."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
