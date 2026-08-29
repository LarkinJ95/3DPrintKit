import SwiftUI

/// PrintKit design tokens.
/// Visual language: precision instrument + modern Apple utility.
/// Neutral surfaces, one accent, restrained depth, native typography.
enum PK {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 12
        static let chip: CGFloat = 8
    }

    /// A color that resolves differently in light and dark mode.
    /// Used where a system semantic color is tuned for fills but too light
    /// or too dark to carry a symbol at caption size.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    enum StatusColor {
        static let ready = Color.green
        /// Act soon — a due task, a low spool.
        static let attention = Color.orange
        /// Proceed with care — a readiness check that passed with caveats.
        static let warning = PK.adaptive(
            light: Color(red: 0.68, green: 0.48, blue: 0.02),
            dark: Color(red: 0.98, green: 0.80, blue: 0.35)
        )
        /// Blocked — this print cannot proceed as configured.
        static let error = Color.red
        static let info = Color.blue
        static let inactive = Color.gray
    }
}

/// Semantic status used across readiness, inventory, maintenance and more.
/// Always rendered with an icon + label, never by color alone — and the
/// label is drawn at full contrast, with the hue carried by the symbol.
enum PKStatus: String, CaseIterable {
    case ready, attention, warning, error, info, inactive

    var color: Color {
        switch self {
        case .ready: return PK.StatusColor.ready
        case .attention: return PK.StatusColor.attention
        case .warning: return PK.StatusColor.warning
        case .error: return PK.StatusColor.error
        case .info: return PK.StatusColor.info
        case .inactive: return PK.StatusColor.inactive
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        case .inactive: return "circle"
        }
    }

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .attention: return "Attention"
        case .warning: return "Warning"
        case .error: return "Blocked"
        case .info: return "Info"
        case .inactive: return "Inactive"
        }
    }

    /// Sort weight for attention lists — most urgent first.
    var urgency: Int {
        switch self {
        case .error: return 0
        case .attention: return 1
        case .warning: return 2
        case .info: return 3
        case .ready: return 4
        case .inactive: return 5
        }
    }
}
