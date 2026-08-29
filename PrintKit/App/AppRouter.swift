import SwiftUI

/// Central navigation / deep-link router.
///
/// Supported URLs (also used by App Intents and QR codes):
///   3dprintkit://home
///   3dprintkit://scan                -> NFC scan sheet
///   3dprintkit://add-spool
///   3dprintkit://spool/<uuid>        -> spool detail
///   3dprintkit://drying              -> start drying
///   3dprintkit://cost                -> cost calculator
///   3dprintkit://compare
///   3dprintkit://troubleshoot
///   3dprintkit://readiness
///   3dprintkit://maintenance
enum AppTab: Int, Hashable {
    case home, spools, materials, tools, garage
}

/// A destination that is a *place* in the app rather than a task.
///
/// Places are always pushed onto their tab's navigation stack, so they arrive
/// with a back button no matter whether the user came from a list row, a Home
/// shortcut, a Siri intent, or a deep link. Tasks — scan, add, log — are
/// presented as sheets and own their own Cancel/Save buttons.
enum PushDestination: Hashable {
    case printCost
    case troubleshoot
    case calibration
    case compareMaterials
    case readiness
    /// Search results push straight to the item the user picked.
    case material(String)
    case troubleshootIssue(String)

    @ViewBuilder
    var view: some View {
        switch self {
        case .printCost: CostCalculatorView()
        case .troubleshoot: TroubleshootListView()
        case .calibration: CalibrationListView()
        case .compareMaterials: MaterialCompareView()
        case .readiness: ReadinessCheckView()
        case .material(let id):
            if let material = MaterialLibrary.shared.material(for: id) {
                MaterialDetailView(material: material)
            }
        case .troubleshootIssue(let id):
            if let issue = TroubleshootingLibrary.issues.first(where: { $0.id == id }) {
                TroubleshootDetailView(issue: issue)
            }
        }
    }
}

enum QuickAction: String, Identifiable, CaseIterable {
    case scanSpool, addSpool, writeNFC, compareMaterials, startDrying, logPrint,
         newProject, printCost, troubleshoot, startCalibration, logMaintenance, checkReadiness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanSpool: return "Scan Spool"
        case .addSpool: return "Add Spool"
        case .writeNFC: return "Write NFC Tag"
        case .compareMaterials: return "Compare Materials"
        case .startDrying: return "Start Drying"
        case .logPrint: return "Log Print"
        case .newProject: return "New Project"
        case .printCost: return "Print Cost"
        case .troubleshoot: return "Troubleshoot"
        case .startCalibration: return "Start Calibration"
        case .logMaintenance: return "Log Maintenance"
        case .checkReadiness: return "Check Readiness"
        }
    }

    var systemImage: String {
        switch self {
        case .scanSpool: return "wave.3.right.circle"
        case .addSpool: return "plus.circle"
        case .writeNFC: return "pencil.circle"
        case .compareMaterials: return "rectangle.split.2x1"
        case .startDrying: return "humidity"
        case .logPrint: return "printer.fill"
        case .newProject: return "folder.badge.plus"
        case .printCost: return "dollarsign.circle"
        case .troubleshoot: return "wrench.and.screwdriver"
        case .startCalibration: return "ruler"
        case .logMaintenance: return "screwdriver"
        case .checkReadiness: return "checkmark.shield"
        }
    }

    /// The tab this action belongs to.
    var tab: AppTab {
        switch self {
        case .scanSpool, .addSpool, .writeNFC, .startDrying: return .spools
        case .compareMaterials: return .materials
        case .printCost, .troubleshoot, .startCalibration: return .tools
        case .logPrint, .newProject, .logMaintenance: return .garage
        case .checkReadiness: return .home
        }
    }

    /// Non-nil for actions that open a place rather than start a task.
    var destination: PushDestination? {
        switch self {
        case .printCost: return .printCost
        case .troubleshoot: return .troubleshoot
        case .startCalibration: return .calibration
        case .compareMaterials: return .compareMaterials
        case .checkReadiness: return .readiness
        default: return nil
        }
    }

    /// The four actions surfaced on Home. Everything else lives in search.
    static let homeShortcuts: [QuickAction] = [.scanSpool, .logPrint, .startDrying, .printCost]
}

@Observable
final class AppRouter {
    /// Single shared instance — App Intents and deep links both route through it.
    static let shared = AppRouter()

    var selectedTab: AppTab = .home
    /// Sheet-presented tasks only. Places go through `paths`.
    var quickAction: QuickAction?
    var deepLinkSpoolID: UUID?
    var paths: [AppTab: [PushDestination]] = [:]

    func path(for tab: AppTab) -> Binding<[PushDestination]> {
        Binding(
            get: { [weak self] in self?.paths[tab] ?? [] },
            set: { [weak self] in self?.paths[tab] = $0 }
        )
    }

    func handle(url: URL) {
        guard ["3dprintkit", "printkit"].contains(url.scheme?.lowercased()) else { return }
        let host = url.host ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch host {
        case "home": selectedTab = .home
        case "spools": selectedTab = .spools
        case "materials": selectedTab = .materials
        case "tools": selectedTab = .tools
        case "garage": selectedTab = .garage
        case "scan": perform(.scanSpool)
        case "add-spool": perform(.addSpool)
        case "spool":
            if let id = UUID(uuidString: path) {
                selectedTab = .spools
                deepLinkSpoolID = id
            }
        case "drying": perform(.startDrying)
        case "cost": perform(.printCost)
        case "compare": perform(.compareMaterials)
        case "troubleshoot": perform(.troubleshoot)
        case "readiness": perform(.checkReadiness)
        case "maintenance": perform(.logMaintenance)
        default:
            break
        }
    }

    func perform(_ action: QuickAction) {
        selectedTab = action.tab
        if let destination = action.destination {
            // Replace rather than append, so invoking the same shortcut twice
            // doesn't stack duplicates on the tab's back stack.
            paths[action.tab] = [destination]
        } else {
            quickAction = action
        }
    }

    /// Opens a place on a given tab, replacing whatever that tab had pushed.
    func push(_ destination: PushDestination, on tab: AppTab) {
        selectedTab = tab
        paths[tab] = [destination]
    }

    /// Opens a spool's detail from anywhere.
    func openSpool(_ id: UUID) {
        selectedTab = .spools
        deepLinkSpoolID = id
    }

    func clearQuickAction() { quickAction = nil }
}
