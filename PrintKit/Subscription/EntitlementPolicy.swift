import Foundation

/// What each tier grants.
///
/// This table is the whole policy. Moving a capability between tiers, changing
/// a free limit, or making projects free again is an edit here and nowhere
/// else — no screen, service, or view model encodes a tier boundary.
///
/// Kept in step with `packages/shared-config/src/index.ts`, which holds the
/// same table for the Worker and the web app. Change them together.
struct EntitlementSet: Sendable {
    let capabilities: Set<Capability>
    let quotas: [RecordKind: Quota]

    func quota(for kind: RecordKind) -> Quota {
        quotas[kind] ?? .unlimited
    }
}

enum EntitlementPolicy {
    /// Free: a genuinely useful toolkit with a small real inventory.
    ///
    /// `projects: .limited(0)` is decision D1 in docs/product-plan.md —
    /// projects are Pro at launch, expressed as a quota so the decision can be
    /// reversed by changing this one number.
    static let free = EntitlementSet(
        capabilities: [],
        quotas: [
            .spools: .limited(10),
            .printers: .limited(1),
            .projects: .limited(0)
        ]
    )

    /// Pro: everything, with no ceiling.
    static let pro = EntitlementSet(
        capabilities: Set(Capability.allCases),
        quotas: [
            .spools: .unlimited,
            .printers: .unlimited,
            .projects: .unlimited
        ]
    )

    static func set(isPro: Bool) -> EntitlementSet {
        isPro ? pro : free
    }
}
