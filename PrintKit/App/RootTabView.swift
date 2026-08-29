import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(AppRouter.self) private var router

    /// `@AppStorage` rather than `AppSettings`, whose properties are computed
    /// over `UserDefaults` and therefore invisible to `@Observable` tracking.
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @State private var showWelcome = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            tab(.home) { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            tab(.spools) { SpoolListView() }
                .tabItem { Label("Inventory", systemImage: "circle.dashed.inset.filled") }
                .tag(AppTab.spools)
            tab(.materials) { MaterialListView() }
                .tabItem { Label("Reference", systemImage: "books.vertical") }
                .tag(AppTab.materials)
            tab(.tools) { ToolsHomeView() }
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(AppTab.tools)
            tab(.garage) { GarageHomeView() }
                .tabItem { Label("Garage", systemImage: "printer") }
                .tag(AppTab.garage)
        }
        .tint(.accentColor)
        .sheet(item: $router.quickAction) { action in
            QuickActionSheet(action: action)
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                hasCompletedWelcome = true
                showWelcome = false
            }
        }
        .task {
            // A returning user with a valid Keychain session has already made
            // this choice, so don't ask again after a reinstall.
            if AuthManager.shared.isSignedIn { hasCompletedWelcome = true }
            showWelcome = !hasCompletedWelcome
        }
    }

    /// Every tab is a navigation stack whose path the router can drive, so a
    /// Home shortcut, a Siri intent, and a deep link all land on the same
    /// pushed screen with a normal back button.
    private func tab<Root: View>(_ appTab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: router.path(for: appTab)) {
            root()
                .navigationDestination(for: PushDestination.self) { $0.view }
        }
    }
}

/// Routes task-shaped quick actions (Home shortcuts, search, App Intents) to
/// the right sheet. Places are pushed instead — see `PushDestination`.
struct QuickActionSheet: View {
    let action: QuickAction

    var body: some View {
        NavigationStack {
            switch action {
            case .scanSpool:
                NFCScanView()
            case .addSpool:
                SpoolFormView(spool: nil)
            case .writeNFC:
                NFCWriteFlowView()
            case .startDrying:
                DryingStartView()
            case .logPrint:
                PrintLogFormView(record: nil)
            case .newProject:
                ProjectFormView(project: nil)
            case .logMaintenance:
                MaintenanceLogFormView()
            case .compareMaterials, .printCost, .troubleshoot, .startCalibration, .checkReadiness:
                // Places are pushed, never presented. Reachable only if a new
                // case is added without giving it a presentation style.
                EmptyView()
            }
        }
    }
}
