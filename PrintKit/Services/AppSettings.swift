import SwiftUI

/// App-wide user preferences persisted in UserDefaults.
/// Exposed to the view hierarchy with @Environment.
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private init() {}

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    var metricUnits: Bool {
        get { bool("metricUnits", true) }
        set { defaults.set(newValue, forKey: "metricUnits") }
    }
    var temperatureCelsius: Bool {
        get { bool("temperatureCelsius", true) }
        set { defaults.set(newValue, forKey: "temperatureCelsius") }
    }
    var currencyCode: String {
        get { defaults.string(forKey: "currencyCode") ?? Locale.current.currency?.identifier ?? "USD" }
        set { defaults.set(newValue, forKey: "currencyCode") }
    }
    var defaultDiameter: Double {
        get { defaults.object(forKey: "defaultDiameter") == nil ? 1.75 : defaults.double(forKey: "defaultDiameter") }
        set { defaults.set(newValue, forKey: "defaultDiameter") }
    }
    var defaultSpoolGrams: Double {
        get { defaults.object(forKey: "defaultSpoolGrams") == nil ? 1000 : defaults.double(forKey: "defaultSpoolGrams") }
        set { defaults.set(newValue, forKey: "defaultSpoolGrams") }
    }
    var defaultPrinterID: UUID? {
        get { defaults.string(forKey: "defaultPrinterID").flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: "defaultPrinterID") }
    }
    var defaultMaterialID: String {
        get { defaults.string(forKey: "defaultMaterialID") ?? "pla" }
        set { defaults.set(newValue, forKey: "defaultMaterialID") }
    }
    var reservePercent: Double {
        get { defaults.object(forKey: "reservePercent") == nil ? 10 : defaults.double(forKey: "reservePercent") }
        set { defaults.set(newValue, forKey: "reservePercent") }
    }
    var lowSpoolThresholdGrams: Double {
        get { defaults.object(forKey: "lowSpoolThreshold") == nil ? 150 : defaults.double(forKey: "lowSpoolThreshold") }
        set { defaults.set(newValue, forKey: "lowSpoolThreshold") }
    }
    var hapticsEnabled: Bool {
        get { bool("hapticsEnabled", true) }
        set { defaults.set(newValue, forKey: "hapticsEnabled") }
    }
    var dryingNotificationsEnabled: Bool {
        get { bool("dryingNotificationsEnabled", true) }
        set { defaults.set(newValue, forKey: "dryingNotificationsEnabled") }
    }
    var maintenanceNotificationsEnabled: Bool {
        get { bool("maintenanceNotificationsEnabled", false) }
        set { defaults.set(newValue, forKey: "maintenanceNotificationsEnabled") }
    }
    var sampleDataLoaded: Bool {
        get { bool("sampleDataLoaded", false) }
        set { defaults.set(newValue, forKey: "sampleDataLoaded") }
    }
}

// MARK: - Formatting helpers

enum Format {
    static func grams(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.2f kg", value / 1000)
        }
        return String(format: "%.0f g", value)
    }

    static func length(meters: Double, metric: Bool = AppSettings.shared.metricUnits) -> String {
        if metric {
            return String(format: meters >= 100 ? "%.0f m" : "%.1f m", meters)
        }
        return String(format: "%.0f ft", meters * 3.28084)
    }

    static func temperature(_ celsius: Double, useCelsius: Bool = AppSettings.shared.temperatureCelsius) -> String {
        if useCelsius {
            return String(format: "%.0f °C", celsius)
        }
        return String(format: "%.0f °F", celsius * 9 / 5 + 32)
    }

    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func currency(_ value: Double, code: String = AppSettings.shared.currencyCode) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Haptics

enum Haptics {
    static func success() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func light() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Color hex helpers

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        let r, g, b, a: Double
        if cleaned.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Returns black or white, whichever is more readable on this color.
    func readableForeground(hex: String) -> Color {
        var cleaned = hex
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return .white }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6 ? .black : .white
    }
}
