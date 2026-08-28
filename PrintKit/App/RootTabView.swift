import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            NavigationStack { SpoolListView() }
                .tabItem { Label("Spools", systemImage: "circle.dashed") }
                .tag(AppTab.spools)
            NavigationStack { MaterialListView() }
                .tabItem { Label("Materials", systemImage: "square.stack.3d.up") }
                .tag(AppTab.materials)
            NavigationStack { ToolsHomeView() }
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(AppTab.tools)
            NavigationStack { GarageHomeView() }
                .tabItem { Label("Garage", systemImage: "printer") }
                .tag(AppTab.garage)
        }
        .tint(.accentColor)
        .sheet(item: $router.quickAction) { action in
            QuickActionSheet(action: action)
        }
    }
}

/// Routes quick actions (Home shortcuts, Command Center, App Intents)
/// to the right sheet or view.
struct QuickActionSheet: View {
    let action: QuickAction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            switch action {
            case .scanSpool:
                NFCScanView()
            case .addSpool:
                SpoolFormView(spool: nil)
            case .writeNFC:
                NFCWriteFlowView()
            case .compareMaterials:
                MaterialCompareView()
            case .startDrying:
                DryingStartView()
            case .logPrint:
                PrintLogFormView(record: nil)
            case .newProject:
                ProjectFormView(project: nil)
            case .printCost:
                CostCalculatorView()
            case .troubleshoot:
                TroubleshootListView()
            case .startCalibration:
                CalibrationListView()
            case .logMaintenance:
                MaintenanceLogFormView()
            case .checkReadiness:
                ReadinessCheckView()
            }
        }
    }
}
