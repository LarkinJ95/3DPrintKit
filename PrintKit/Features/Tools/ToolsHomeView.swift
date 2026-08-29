import SwiftUI

struct ToolsHomeView: View {
    var body: some View {
        List {
            Section("Calculators") {
                ToolRow(title: "Scale-Based Filament Calculator", subtitle: "Gross weight → remaining g, %, m", icon: "scalemass") { ScaleCalculatorView() }
                ToolRow(title: "Length / Weight Converter", subtitle: "g ↔ kg ↔ m ↔ ft ↔ volume ↔ %", icon: "arrow.left.arrow.right") { ConverterView() }
                ToolLink(title: "Print Cost Calculator", subtitle: "Full cost & pricing model", icon: "dollarsign.circle", value: .printCost)
                ToolRow(title: "Volumetric Flow", subtitle: "mm³/s and max speed", icon: "speedometer") { FlowRateView() }
                ToolRow(title: "Print Estimator", subtitle: "Per-part filament, time, cost", icon: "function") { PrintEstimatorView() }
                ToolRow(title: "Multi-Spool Planner", subtitle: "Combine partial spools", icon: "circle.grid.2x2") { MultiSpoolPlannerView() }
                ToolRow(title: "Multicolor / AMS Planner", subtitle: "Per-color filament check", icon: "paintpalette") { AMSPlannerView() }
            }
            Section("Dimensional") {
                ToolRow(title: "Shrinkage / Scale Compensation", subtitle: "Designed vs measured per axis", icon: "arrow.up.left.and.arrow.down.right") { ShrinkageView() }
                ToolRow(title: "Hole Compensation", subtitle: "Measured vs designed holes", icon: "circle.circle") { HoleCompensationView() }
                ToolRow(title: "Tolerance Library", subtitle: "Your tested fits", icon: "ruler") { ToleranceLibraryView() }
                ToolRow(title: "Fastener Reference", subtitle: "Holes, inserts, bearings", icon: "screwdriver") { FastenerReferenceView() }
                ToolRow(title: "Thread Reference", subtitle: "Printed threads & inserts", icon: "bolt.horizontal") { ThreadReferenceView() }
            }
            Section("Guidance") {
                ToolLink(title: "Calibration Center", subtitle: "Guided calibration workflows", icon: "checklist", value: .calibration)
                ToolLink(title: "Troubleshooting", subtitle: "Diagnose print problems", icon: "stethoscope", value: .troubleshoot)
            }
            Section("NFC Utilities") {
                ToolRow(title: "Tag Tools", subtitle: "Read, write, erase, lock NDEF tags", icon: "wave.3.right") { NFCUtilitiesView() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tools")
    }
}

/// Label shared by both row kinds, so a tool looks the same whether it is
/// pushed by view or by routed value.
private struct ToolLabel: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
        }
    }
}

/// Generic over its destination so the view is only built when the row is
/// tapped, rather than eagerly type-erased through `AnyView` on every layout.
struct ToolRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            ToolLabel(title: title, subtitle: subtitle, icon: icon)
        }
    }
}

/// For tools that are also reachable from Home, search, Siri, and deep links —
/// they route through `PushDestination` so every entry point lands identically.
struct ToolLink: View {
    let title: String
    let subtitle: String
    let icon: String
    let value: PushDestination

    var body: some View {
        NavigationLink(value: value) {
            ToolLabel(title: title, subtitle: subtitle, icon: icon)
        }
    }
}
