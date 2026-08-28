import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen / Dynamic Island presentation for an active drying session.
struct DryingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DryingActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.spoolName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Drying at \(Int(context.state.targetTempC)) °C")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Text("remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.spoolName, systemImage: "flame.fill")
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.targetTempC)) °C")
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Drying")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                            .font(.callout.monospacedDigit().weight(.medium))
                    }
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Drying")
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Drying in progress")
            }
        }
    }
}
