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
        static let card: CGFloat = 10
        static let chip: CGFloat = 6
    }

    enum StatusColor {
        static let ready = Color.green
        static let attention = Color.orange
        static let error = Color.red
        static let info = Color.blue
        static let inactive = Color.gray
    }
}

/// Semantic status used across readiness, inventory, maintenance and more.
/// Always rendered with an icon + label, never by color alone.
enum PKStatus: String, CaseIterable {
    case ready, attention, warning, error, info, inactive

    var color: Color {
        switch self {
        case .ready: return PK.StatusColor.ready
        case .attention, .warning: return PK.StatusColor.attention
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
        case .error: return "Issue"
        case .info: return "Info"
        case .inactive: return "Inactive"
        }
    }
}
