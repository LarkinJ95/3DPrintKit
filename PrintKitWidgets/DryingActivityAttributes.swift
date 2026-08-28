import ActivityKit
import Foundation

/// Shared between the PrintKit app target and the PrintKitWidgets extension.
/// Both targets must include this file in their Compile Sources phase.
struct DryingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When drying finishes (used for the countdown timer).
        public var endDate: Date
        /// Dryer target temperature in Celsius.
        public var targetTempC: Double

        public init(endDate: Date, targetTempC: Double) {
            self.endDate = endDate
            self.targetTempC = targetTempC
        }
    }

    /// DryingSession UUID as string — lets the app end the right activity.
    public var sessionID: String
    public var spoolName: String

    public init(sessionID: String, spoolName: String) {
        self.sessionID = sessionID
        self.spoolName = spoolName
    }
}
