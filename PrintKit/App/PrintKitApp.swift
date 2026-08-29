import SwiftUI
import SwiftData

@main
struct PrintKitApp: App {
    @State private var router = AppRouter.shared
    @State private var settings = AppSettings.shared
    @State private var entitlements = EntitlementService.shared
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                migrationPlan: PrintKitMigrationPlan.self,
                configurations: ModelConfiguration("PrintKit")
            )
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
        let seedContext = ModelContext(container)
        DataSeeder.seedIfNeeded(context: seedContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(router)
                .environment(settings)
                .environment(entitlements)
                .task {
                    // Start observing StoreKit before any purchase can begin,
                    // then reconcile with the server. Missing this drops
                    // Ask to Buy approvals and out-of-app renewals.
                    PurchaseManager.shared.start()
                    await entitlements.refresh()
                }
                .onOpenURL { router.handle(url: $0) }
        }
        .modelContainer(container)
    }
}
