import SwiftUI
import SwiftData

@main
struct PrintKitApp: App {
    @State private var router = AppRouter.shared
    @State private var settings = AppSettings.shared
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
                .onOpenURL { router.handle(url: $0) }
        }
        .modelContainer(container)
    }
}
