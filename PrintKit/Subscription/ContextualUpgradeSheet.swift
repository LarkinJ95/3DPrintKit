import SwiftUI

/// The compact sheet shown when someone deliberately reaches for a Pro feature.
///
/// It explains the one thing they just tried to do, then gets out of the way.
/// The full paywall opens only if they ask for it — a locked feature never
/// throws the whole price list at someone mid-task, and "Not Now" is never
/// punished by asking again on the next screen.
struct ContextualUpgradeSheet: View {
    let reason: BlockReason
    var onViewPro: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: PK.Spacing.lg) {
            VStack(alignment: .leading, spacing: PK.Spacing.sm) {
                Text(reason.title)
                    .font(.title3.weight(.semibold))
                Text(reason.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("Included with 3dPrintKit Pro", systemImage: "checkmark.seal")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)

            HStack(spacing: PK.Spacing.md) {
                Button("Not Now") { dismiss() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("View Pro") {
                    dismiss()
                    onViewPro()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(PK.Spacing.xl)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .onAppear {
            SubscriptionAnalytics.log(.featureAttempted(key: reason.analyticsKey))
            if case .quota(let kind, let limit, _) = reason {
                SubscriptionAnalytics.log(.quotaLimitReached(kind: kind, limit: limit))
            }
        }
    }
}

// MARK: - Presentation helper

/// Drives both sheets from one piece of state, so a screen adds a gate with a
/// single modifier instead of hand-rolling two `@State` flags each time.
@Observable
final class UpgradePrompt {
    var reason: BlockReason?
    var showPaywall = false

    /// Run `action` when entitled; otherwise explain what Pro adds.
    func attempt(_ result: GateResult, action: () -> Void) {
        switch result {
        case .allowed:
            action()
        case .blocked(let blockReason):
            reason = blockReason
        }
    }

    var isPresentingReason: Bool {
        get { reason != nil }
        set { if !newValue { reason = nil } }
    }
}

extension View {
    /// Attach the contextual sheet and the paywall to a screen.
    func upgradePrompt(_ prompt: UpgradePrompt, source: SubscriptionAnalytics.Source = .contextual) -> some View {
        self
            .sheet(isPresented: Binding(
                get: { prompt.isPresentingReason },
                set: { prompt.isPresentingReason = $0 }
            )) {
                if let reason = prompt.reason {
                    ContextualUpgradeSheet(reason: reason) { prompt.showPaywall = true }
                }
            }
            .sheet(isPresented: Binding(
                get: { prompt.showPaywall },
                set: { prompt.showPaywall = $0 }
            )) {
                PaywallView(source: source)
            }
    }
}

// MARK: - PRO badge

/// A restrained marker for a Pro-only row. Text, not a lock icon — the app
/// should still look elegant to someone on Free.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Included with Pro")
    }
}
