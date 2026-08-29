import Foundation

/// The entitlement vocabulary.
///
/// Everything outside `Subscription/` speaks in these terms — a screen asks
/// "may I write an NFC tag?", never "is the user Pro?". That indirection is
/// what lets pricing, limits, and tier boundaries change in one place.

// MARK: - Capabilities

enum Capability: String, CaseIterable, Sendable {
    case canUseCloudSync
    case canAccessWeb
    case canWriteNFC
    case canAddUnlimitedSpools
    case canAddUnlimitedPrinters
    case canAddUnlimitedProjects
    case canUseAdvancedAnalytics
    case canUsePrintReadiness
    case canUsePersonalKnowledge
    case canUseAdvancedExport
    case canUseAdvancedMaterialTools
    case canUsePhotos
    case canUseMaintenanceAndDrying
    case canUseHardwareInventory
    case canUseRecords
}

// MARK: - Quotas

/// Record types that carry a creation quota.
enum RecordKind: String, CaseIterable, Sendable {
    case spools, printers, projects

    var singular: String {
        switch self {
        case .spools: return "spool"
        case .printers: return "printer"
        case .projects: return "project"
        }
    }

    var plural: String { rawValue }
}

enum Quota: Equatable, Sendable {
    case limited(Int)
    case unlimited

    var limit: Int? {
        if case .limited(let value) = self { return value }
        return nil
    }
}

// MARK: - Feature keys

/// A Pro capability as the user encounters it. Drives the contextual upgrade
/// sheet's copy and the `pro_feature_attempted` analytics event, so a screen
/// never writes its own upsell text.
enum FeatureKey: String, Sendable {
    case nfcWrite
    case cloudSync
    case desktopWeb
    case projects
    case printHistory
    case printReadiness
    case analytics
    case personalKnowledge
    case advancedExport
    case materialTools
    case photos
    case maintenanceAndDrying
    case hardwareInventory

    var title: String {
        switch self {
        case .nfcWrite: return "NFC Spool Writing"
        case .cloudSync: return "Cloud Backup & Sync"
        case .desktopWeb: return "3dPrintKit Desktop"
        case .projects: return "Projects"
        case .printHistory: return "Print History"
        case .printReadiness: return "Print Readiness"
        case .analytics: return "Print & Cost Analytics"
        case .personalKnowledge: return "Personal Printing Knowledge"
        case .advancedExport: return "Advanced Export"
        case .materialTools: return "Advanced Material Tools"
        case .photos: return "Photos & Attachments"
        case .maintenanceAndDrying: return "Maintenance & Drying"
        case .hardwareInventory: return "Nozzles, Plates & Accessories"
        }
    }

    /// One sentence, written from the user's side of the screen: what the
    /// feature does for them, not what the app unlocks.
    var explanation: String {
        switch self {
        case .nfcWrite:
            return "Create reusable NFC tags for your filament spools and instantly identify them with 3dPrintKit."
        case .cloudSync:
            return "Back up your workshop and keep every device showing the same inventory, history, and profiles."
        case .desktopWeb:
            return "Work with your whole workshop on a full-size screen — inventory, planning, and analytics."
        case .projects:
            return "Group prints into a project and watch filament, time, and cost roll up as you go."
        case .printHistory:
            return "Log what you print so filament, printer hours, and cost stay accurate on their own."
        case .printReadiness:
            return "Check a printer, spool, and profile against the job before you start it."
        case .analytics:
            return "See where your filament, money, and failures actually went over time."
        case .personalKnowledge:
            return "Turn your own prints into what you know — what worked, what didn't, and why."
        case .advancedExport:
            return "Export your full workshop in richer formats for spreadsheets and record keeping."
        case .materialTools:
            return "Compare up to five materials, find substitutes, and check printer compatibility."
        case .photos:
            return "Attach photos to spools and projects, backed up with the rest of your workshop."
        case .maintenanceAndDrying:
            return "Track maintenance intervals and drying sessions so nothing quietly goes overdue."
        case .hardwareInventory:
            return "Keep nozzles, build plates, and accessories alongside the printers they belong to."
        }
    }

    /// The capability this feature needs, so a screen only names the feature.
    var capability: Capability {
        switch self {
        case .nfcWrite: return .canWriteNFC
        case .cloudSync: return .canUseCloudSync
        case .desktopWeb: return .canAccessWeb
        case .projects: return .canAddUnlimitedProjects
        case .printHistory: return .canUseRecords
        case .printReadiness: return .canUsePrintReadiness
        case .analytics: return .canUseAdvancedAnalytics
        case .personalKnowledge: return .canUsePersonalKnowledge
        case .advancedExport: return .canUseAdvancedExport
        case .materialTools: return .canUseAdvancedMaterialTools
        case .photos: return .canUsePhotos
        case .maintenanceAndDrying: return .canUseMaintenanceAndDrying
        case .hardwareInventory: return .canUseHardwareInventory
        }
    }
}

// MARK: - Gate results

enum BlockReason: Sendable {
    case quota(RecordKind, limit: Int, current: Int)
    case proFeature(FeatureKey)

    /// Headline for the contextual sheet. Factual, never scolding.
    var title: String {
        switch self {
        case .quota(let kind, let limit, _):
            return limit == 0
                ? "\(kind.plural.capitalized) are part of Pro"
                : "You've reached the \(limit)-\(kind.singular) Free limit"
        case .proFeature(let feature):
            return feature.title
        }
    }

    var message: String {
        switch self {
        case .quota(let kind, let limit, let current):
            return limit == 0
                ? "3dPrintKit Pro adds unlimited \(kind.plural), along with cloud sync and the desktop app."
                : "You have \(current) \(current == 1 ? kind.singular : kind.plural). Pro removes the limit — and every \(kind.singular) you already have stays exactly where it is."
        case .proFeature(let feature):
            return feature.explanation
        }
    }

    /// Stable identifier for `pro_feature_attempted`.
    var analyticsKey: String {
        switch self {
        case .quota(let kind, _, _): return "quota.\(kind.rawValue)"
        case .proFeature(let feature): return feature.rawValue
        }
    }
}

enum GateResult: Sendable {
    case allowed
    case blocked(BlockReason)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    var blockReason: BlockReason? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }
}
