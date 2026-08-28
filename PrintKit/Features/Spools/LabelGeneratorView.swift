import SwiftUI
import UIKit

/// Printable spool labels with QR, exported as PDF.
struct LabelGeneratorView: View {
    let spool: Spool
    @Environment(\.dismiss) private var dismiss

    enum LabelPreset: String, CaseIterable, Identifiable {
        case small = "62 × 29 mm"
        case medium = "90 × 50 mm"
        case large = "102 × 74 mm"
        case custom = "Custom"
        var id: String { rawValue }

        var sizeMM: CGSize {
            switch self {
            case .small: return CGSize(width: 62, height: 29)
            case .medium: return CGSize(width: 90, height: 50)
            case .large: return CGSize(width: 102, height: 74)
            case .custom: return CGSize(width: 90, height: 50)
            }
        }
    }

    @State private var preset: LabelPreset = .medium
    @State private var customWidth = 90.0
    @State private var customHeight = 50.0

    private var sizeMM: CGSize {
        preset == .custom ? CGSize(width: customWidth, height: customHeight) : preset.sizeMM
    }

    private var material: FilamentMaterial? {
        MaterialLibrary.shared.material(for: spool.materialID)
    }

    var body: some View {
        Form {
            Section("Label Size") {
                Picker("Preset", selection: $preset) {
                    ForEach(LabelPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                if preset == .custom {
                    Stepper(value: $customWidth, in: 40...150, step: 1) {
                        HStack { Text("Width"); Spacer(); Text("\(Int(customWidth)) mm").monospacedDigit() }
                    }
                    Stepper(value: $customHeight, in: 20...100, step: 1) {
                        HStack { Text("Height"); Spacer(); Text("\(Int(customHeight)) mm").monospacedDigit() }
                    }
                }
            }

            Section("Preview") {
                LabelPreview(spool: spool, material: material)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Section {
                ShareLink(item: renderPDF(), preview: SharePreview("Spool Label", image: Image(systemName: "doc"))) {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Spool Label")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }

    private func renderPDF() -> URL {
        let mmToPoints: CGFloat = 72.0 / 25.4
        let pageRect = CGRect(x: 0, y: 0,
                              width: sizeMM.width * mmToPoints,
                              height: sizeMM.height * mmToPoints)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("3DPrintKit-Label-\(String(spool.id.uuidString.prefix(8))).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let label = LabelPreview(spool: spool, material: material)
            let host = UIHostingController(rootView: label)
            host.view.frame = CGRect(origin: .zero, size: pageRect.size)
            host.view.backgroundColor = .white
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        try? data.write(to: url)
        return url
    }
}

struct LabelPreview: View {
    let spool: Spool
    let material: FilamentMaterial?

    var body: some View {
        HStack(spacing: 10) {
            QRCodeView(content: SpoolTagPayload(spool: spool).qrString)
                .frame(width: 90, height: 90)
            VStack(alignment: .leading, spacing: 2) {
                Text(spool.displayName)
                    .font(.system(size: 13, weight: .bold))
                if let material {
                    Text("\(material.name) · \(material.nozzleRangeText) · Bed \(material.bedRangeText)")
                        .font(.system(size: 9))
                    Text("Dry \(material.dryTemp) °C / \(material.dryHours)h")
                        .font(.system(size: 9))
                }
                Text("Remaining \(Format.grams(spool.currentWeightG)) · Opened \(Format.date(spool.openedDate))")
                    .font(.system(size: 9))
                Text("ID \(String(spool.id.uuidString.prefix(8)))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.separator)))
        .foregroundStyle(.black)
    }
}
