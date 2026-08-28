import Foundation
import UserNotifications

enum NotificationService {
    static let dryingCategory = "printkit.drying"
    static let maintenanceCategory = "printkit.maintenance"

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Schedule a local completion notification for a drying session.
    static func scheduleDryingCompletion(session: DryingSession, spoolName: String) {
        guard AppSettings.shared.dryingNotificationsEnabled else { return }
        let interval = session.plannedEnd.timeIntervalSinceNow
        guard interval > 5 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Drying Complete"
        content.body = "\(spoolName) finished drying at \(Int(session.targetTempC)) °C."
        content.sound = .default
        content.categoryIdentifier = dryingCategory

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: "drying-\(session.id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelDryingCompletion(sessionID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["drying-\(sessionID.uuidString)"])
    }

    /// Daily-at-9am reminder when desiccant regeneration is due.
    static func scheduleDesiccantReminder(unit: DesiccantUnit) {
        let content = UNMutableNotificationContent()
        content.title = "Desiccant Check"
        content.body = "\(unit.containerName): \(unit.desiccantType) was last regenerated \(Format.date(unit.lastRegenerated))."
        content.sound = .default

        var components = DateComponents()
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "desiccant-\(unit.id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
