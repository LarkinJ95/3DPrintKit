import SwiftUI

struct ToolsHomeView: View {
    var body: some View {
        List {
            Section("Calculators") {
                ToolRow(title: "Scale-Based Filament Calculator", subtitle: "Gross weight → remaining g, %, m", icon: "scalemass", destination: AnyView(ScaleCalculatorView()))
                ToolRow(title: "Length / Weight Converter", subtitle: "g ↔ kg ↔ m ↔ ft ↔ volume ↔ %", icon: "arrow.left.arrow.right", destination: AnyView(ConverterView()))
                ToolRow(title: "Print Cost Calculator", subtitle: "Full cost & pricing model", icon: "dollarsign.circle", destination: AnyView(CostCalculatorView()))
                ToolRow(title: "Volumetric Flow", subtitle: "mm³/s and max speed", icon: "speedometer", destination: AnyView(FlowRateView()))
                ToolRow(title: "Print Estimator", subtitle: "Per-part filament, time, cost", icon: "function", destination: AnyView(PrintEstimatorView()))
                ToolRow(title: "Multi-Spool Planner", subtitle: "Combine partial spools", icon: "circle.grid.2x2", destination: AnyView(MultiSpoolPlannerView()))
                ToolRow(title: "Multicolor / AMS Planner", subtitle: "Per-color filament check", icon: "paintpalette", destination: AnyView(AMSPlannerView()))
            }
            Section("Dimensional") {
                ToolRow(title: "Shrinkage / Scale Compensation", subtitle: "Designed vs measured per axis", icon: "arrow.up.left.and.arrow.down.right", destination: AnyView(ShrinkageView()))
                ToolRow(title: "Hole Compensation", subtitle: "Measured vs designed holes", icon: "circle.circle", destination: AnyView(HoleCompensationView()))
                ToolRow(title: "Tolerance Library", subtitle: "Your tested fits", icon: "ruler", destination: AnyView(ToleranceLibraryView()))
                ToolRow(title: "Fastener Reference", subtitle: "Holes, inserts, bearings", icon: "screwdriver", destination: AnyView(FastenerReferenceView()))
                ToolRow(title: "Thread Reference", subtitle: "Printed threads & inserts", icon: "bolt.horizontal", destination: AnyView(ThreadReferenceView()))
            }
            Section("Guidance") {
                ToolRow(title: "Calibration Center", subtitle: "Guided calibration workflows", icon: "checklist", destination: AnyView(CalibrationListView()))
                ToolRow(title: "Troubleshooting", subtitle: "Diagnose print problems", icon: "stethoscope", destination: AnyView(TroubleshootListView()))
            }
            Section("NFC Utilities") {
                ToolRow(title: "Tag Tools", subtitle: "Read, write, erase, lock NDEF tags", icon: "wave.3.right", destination: AnyView(NFCUtilitiesView()))
            }
        }
        .navigationTitle("Tools")
    }
}

struct ToolRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let destination: AnyView

    var body: some View {
        NavigationLink {
            destination
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 24)
            }
        }
    }
}
