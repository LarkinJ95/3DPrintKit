import SwiftUI
import StoreKit

/// Settings → 3dPrintKit Pro.
///
/// States the plan plainly and offers only the actions that apply to it — a
/// lifetime purchaser is never shown "Manage Subscription" or a renewal date,
/// because there is nothing to manage and nothing to renew.
struct ProSettingsView: View {
    @State private var entitlements = EntitlementService.shared
    @State private var purchases = PurchaseManager.shared
    @State private var showPaywall = false
    @State private var restoreMessage: String?
    @State private var isRestoring = false

    var body: some View {
        List {
            Section {
                LabeledContent("Plan", value: entitlements.planTitle)

                switch entitlements.planDisplay {
                case .lifetime:
                    LabeledContent("Access", value: "Permanent")
                case .trial(let endsAt):
                    if let endsAt {
                        LabeledContent("Trial ends", value: endsAt.formatted(date: .abbreviated, time: .omitted))
                    }
                case .monthly(let renewsAt), .annual(let renewsAt):
                    if let renewsAt {
                        LabeledContent("Renews", value: renewsAt.formatted(date: .abbreviated, time: .omitted))
                    }
                case .expired, .free:
                    EmptyView()
                }

                if entitlements.lastReconcileFailed {
                    PKCallout(
                        status: .info,
                        message: "Your plan couldn't be confirmed with the server just now. Nothing has changed on this device."
                    )
                }
            } header: {
                Text("Status")
            } footer: {
                Text(statusFooter)
            }

            Section {
                if !entitlements.isPro {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("View Pro Benefits", systemImage: "sparkles")
                    }
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("What's included", systemImage: "list.bullet")
                    }
                }

                // Only a live subscription has anything to manage. Lifetime
                // purchasers get no subscription-management actions at all.
                if entitlements.isSubscriptionActive {
                    Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                        Label("Manage Subscription", systemImage: "creditcard")
                    }
                }

                Button {
                    Task { await restore() }
                } label: {
                    if isRestoring {
                        HStack { ProgressView(); Text("Restoring…") }
                    } else {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRestoring)
            }

            if entitlements.isPro {
                Section {
                    ForEach(proInclusions, id: \.self) { item in
                        Label(item, systemImage: "checkmark")
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Included")
                }
            } else {
                Section {
                    LabeledContent("Spools", value: quotaText(.spools))
                    LabeledContent("Printers", value: quotaText(.printers))
                    LabeledContent("Projects", value: quotaText(.projects))
                } header: {
                    Text("Free plan limits")
                } footer: {
                    Text("Reaching a limit never affects what you already have. Everything you've added stays available to view, edit, and export.")
                }
            }
        }
        .navigationTitle("3dPrintKit Pro")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView(source: .settings) }
        .alert("Restore Purchases", isPresented: .constant(restoreMessage != nil)) {
            Button("OK") { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
        .task { await entitlements.refresh() }
    }

    private var statusFooter: String {
        switch entitlements.planDisplay {
        case .lifetime:
            return "You own 3dPrintKit Pro permanently. There is nothing to renew and nothing to cancel."
        case .expired:
            return "Your data is safe. Everything you created is still on this device and in your cloud backup — resubscribing resumes syncing where it left off."
        case .free:
            return "Free includes the material database, every calculator, and a small inventory, with no ads and no time limit."
        case .trial:
            return "Your trial converts to an annual subscription unless you cancel at least 24 hours before it ends."
        case .monthly, .annual:
            return "Thank you for supporting 3dPrintKit."
        }
    }

    private func quotaText(_ kind: RecordKind) -> String {
        switch entitlements.quota(for: kind) {
        case .unlimited: return "Unlimited"
        case .limited(0): return "Pro only"
        case .limited(let limit): return "Up to \(limit)"
        }
    }

    private let proInclusions = [
        "Unlimited spools, printers, and projects",
        "NFC tag writing and spool programming",
        "Cloud backup, sync, and 3dPrintKit Desktop",
        "Print history, projects, and profiles",
        "Maintenance, drying, and hardware inventory",
        "Print Readiness and advanced planning",
        "Cost, waste, and print analytics",
        "Personal Printing Knowledge insights"
    ]

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await purchases.restore()
            await entitlements.refresh()
            SubscriptionAnalytics.log(.purchaseRestored(kind: entitlements.activeKind))
            restoreMessage = entitlements.isPro
                ? "Your 3dPrintKit Pro purchase has been restored."
                : "No previous purchase was found on this Apple ID."
        } catch {
            restoreMessage = error.localizedDescription
        }
    }
}

extension EntitlementService {
    /// True only for a live auto-renewing subscription — the one case where
    /// "Manage Subscription" means anything.
    var isSubscriptionActive: Bool {
        guard isPro, !isLifetime else { return false }
        return true
    }
}
