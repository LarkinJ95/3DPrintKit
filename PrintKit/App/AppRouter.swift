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
        case .writeNFC: return "pencil.and.radiowaves.left.and.right"
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
}

@Observable
final class AppRouter {
    /// Single shared instance — App Intents and deep links both route through it.
    static let shared = AppRouter()

    var selectedTab: AppTab = .home
    var quickAction: QuickAction?
    var deepLinkSpoolID: UUID?

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
        case "scan":
            selectedTab = .spools
            quickAction = .scanSpool
        case "add-spool":
            selectedTab = .spools
            quickAction = .addSpool
        case "spool":
            if let id = UUID(uuidString: path) {
                selectedTab = .spools
                deepLinkSpoolID = id
            }
        case "drying":
            selectedTab = .spools
            quickAction = .startDrying
        case "cost":
            selectedTab = .tools
            quickAction = .printCost
        case "compare":
            selectedTab = .materials
            quickAction = .compareMaterials
        case "troubleshoot":
            selectedTab = .tools
            quickAction = .troubleshoot
        case "readiness":
            selectedTab = .home
            quickAction = .checkReadiness
        case "maintenance":
            selectedTab = .garage
            quickAction = .logMaintenance
        default:
            break
        }
    }

    func perform(_ action: QuickAction) {
        switch action {
        case .compareMaterials: selectedTab = .materials
        case .printCost, .troubleshoot, .startCalibration: selectedTab = .tools
        case .logPrint, .newProject, .logMaintenance: selectedTab = .garage
        case .checkReadiness: selectedTab = .home
        case .scanSpool, .addSpool, .writeNFC, .startDrying: selectedTab = .spools
        }
        quickAction = action
    }

    func clearQuickAction() { quickAction = nil }
}
