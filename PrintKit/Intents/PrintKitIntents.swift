import AppIntents
import Foundation

// MARK: - App shortcuts

/// Exposes PrintKit's core actions to Siri, Spotlight, and the Shortcuts app.
struct PrintKitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanSpoolIntent(),
            phrases: [
                "Scan a spool in \(.applicationName)",
                "Scan NFC spool with \(.applicationName)"
            ],
            shortTitle: "Scan Spool",
            systemImageName: "sensor.tag.radiowaves.forward"
        )
        AppShortcut(
            intent: StartDryingIntent(),
            phrases: ["Start drying filament in \(.applicationName)"],
            shortTitle: "Start Drying",
            systemImageName: "flame"
        )
        AppShortcut(
            intent: LogPrintIntent(),
            phrases: ["Log a print in \(.applicationName)"],
            shortTitle: "Log Print",
            systemImageName: "printer"
        )
        AppShortcut(
            intent: CheckReadinessIntent(),
            phrases: ["Am I ready to print in \(.applicationName)"],
            shortTitle: "Check Readiness",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: PrintCostIntent(),
            phrases: ["Calculate print cost in \(.applicationName)"],
            shortTitle: "Print Cost",
            systemImageName: "dollarsign.circle"
        )
    }
}

// MARK: - Intents

/// Intents are thin bridges into the app: each one opens PrintKit and routes
/// through the same QuickAction system as the Home screen shortcuts, so there
/// is exactly one code path per action.
struct ScanSpoolIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Spool"
    static let description = IntentDescription("Opens 3DPrintKit and starts an NFC spool scan.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.perform(.scanSpool) }
        return .result()
    }
}

struct AddSpoolIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Spool"
    static let description = IntentDescription("Opens the new-spool form in 3DPrintKit.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.perform(.addSpool) }
        return .result()
    }
}

struct StartDryingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Drying"
    static let description = IntentDescription("Opens the drying session setup in 3DPrintKit.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.perform(.startDrying) }
        return .result()
    }
}

struct LogPrintIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Print"
    static let description = IntentDescription("Opens the print logging form in 3DPrintKit.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.perform(.logPrint) }
        return .result()
    }
}

struct CheckReadinessIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Print Readiness"
    static let description = IntentDescription("Runs the pre-flight readiness check in 3DPrintKit.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.perform(.checkReadiness) }
        return .result()
    }
}

struct PrintCostIntent: AppIntent {
    static let title: LocalizedStringResource = "Calculate Print Cost"
    static let description = IntentDescription("Opens the print cost calculator in 3DPrintKit.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.perform(.printCost) }
        return .result()
    }
}

struct TroubleshootIntent: AppIntent {
    static let title: LocalizedStringResource = "Troubleshoot a Print Issue"
    static let description = IntentDescription("Opens the troubleshooting assistant in 3DPrintKit.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppRouter.shared.perform(.troubleshoot) }
        return .result()
    }
}
