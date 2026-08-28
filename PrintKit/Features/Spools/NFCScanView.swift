import SwiftUI
import SwiftData

/// NFC scanning UI: large symbol, explicit states, real progress.
/// Scanning a PrintKit tag opens the spool detail immediately; unknown tags
/// offer to create the spool.
struct NFCScanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var nfc = NFCManager()
    @State private var scannedSpool: Spool?
    @State private var unknownPayload: SpoolTagPayload?
    @State private var showQRScanner = false

    var body: some View {
        VStack(spacing: PK.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                    .frame(width: 190, height: 190)
                    .scaleEffect(nfc.state == .ready ? 1.12 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: nfc.state)
                Image(systemName: symbolForState)
                    .font(.system(size: 72))
                    .foregroundStyle(colorForState)
                    .symbolEffect(.pulse, isActive: nfc.state == .ready || nfc.state == .detected)
            }

            VStack(spacing: PK.Spacing.sm) {
                Text(titleForState)
                    .font(.title3.weight(.semibold))
                Text(subtitleForState)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PK.Spacing.xl)
            }

            if !nfc.tagInfo.isEmpty {
                Text(nfc.tagInfo)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .failed = nfc.state {
                Button("Try Again") { start() }
                    .buttonStyle(.borderedProminent)
            }

            Button {
                showQRScanner = true
            } label: {
                Label("Scan QR Code Instead", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(.bordered)
            .padding(.bottom, PK.Spacing.lg)
        }
        .navigationTitle("Scan Spool")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .navigationDestination(item: $scannedSpool) { SpoolDetailView(spool: $0) }
        .sheet(item: $unknownPayload) { payload in
            NavigationStack { SpoolImportView(payload: payload) }
        }
        .sheet(isPresented: $showQRScanner) {
            NavigationStack { QRScanSheet() }
        }
        .onAppear(perform: start)
        .onDisappear { nfc.cancel() }
    }

    private var symbolForState: String {
        switch nfc.state {
        case .idle, .ready: return "wave.3.right.circle"
        case .detected: return "dot.radiowaves.left.and.right"
        case .reading, .writing, .verifying: return "circle.hexagonpath"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private var colorForState: Color {
        switch nfc.state {
        case .complete: return .green
        case .failed: return .red
        default: return .accentColor
        }
    }

    private var titleForState: String {
        switch nfc.state {
        case .idle: return "Preparing…"
        case .ready: return "Ready to Scan"
        case .detected: return "Tag Detected"
        case .reading: return "Reading…"
        case .writing: return "Writing…"
        case .verifying: return "Verifying…"
        case .complete: return "Done"
        case .failed: return "Couldn't Read Tag"
        }
    }

    private var subtitleForState: String {
        switch nfc.state {
        case .ready: return "Hold the top of your iPhone near the spool tag."
        case .failed(let message): return message
        case .complete: return nfc.detectedPayload != nil ? "Opening spool…" : "Finished."
        default: return ""
        }
    }

    private func start() {
        nfc.begin(mode: .scanSpool)
        nfc.onSpoolScanned = { payload in
            let id = payload.spoolID
            var descriptor = FetchDescriptor<Spool>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let spool = try? context.fetch(descriptor).first {
                scannedSpool = spool
            } else {
                unknownPayload = payload
            }
        }
    }
}

/// Offered when a valid PrintKit tag references a spool that doesn't exist locally.
struct SpoolImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let payload: SpoolTagPayload

    var body: some View {
        Form {
            Section("Tag Contents") {
                KeyValueRow(key: "Spool ID", value: String(payload.spoolID.uuidString.prefix(8)))
                if let manufacturer = payload.manufacturer { KeyValueRow(key: "Manufacturer", value: manufacturer) }
                if let product = payload.product { KeyValueRow(key: "Product", value: product) }
                if let material = payload.material { KeyValueRow(key: "Material", value: material.uppercased()) }
                if let color = payload.color { KeyValueRow(key: "Color", value: color) }
                if let weight = payload.originalWeight { KeyValueRow(key: "Original", value: Format.grams(weight)) }
                if let remaining = payload.remainingWeight { KeyValueRow(key: "Remaining (at tagging)", value: Format.grams(remaining)) }
            }
            Section {
                Text("This spool isn't in your local inventory. Create it from the tag data?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Unknown Spool")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Spool") {
                    let spool = Spool()
                    spool.id = payload.spoolID
                    spool.manufacturer = payload.manufacturer ?? ""
                    spool.productLine = payload.product ?? ""
                    spool.materialID = payload.material ?? AppSettings.shared.defaultMaterialID
                    spool.colorName = payload.color ?? ""
                    spool.diameter = payload.diameter ?? 1.75
                    spool.originalNetWeightG = payload.originalWeight ?? 1000
                    spool.currentWeightG = payload.remainingWeight ?? payload.originalWeight ?? 1000
                    spool.nfcTagWritten = true
                    context.insert(spool)
                    Haptics.success()
                    dismiss()
                }
            }
        }
    }
}

struct QRScanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var scannedSpool: Spool?
    @State private var notFound = false

    var body: some View {
        ZStack {
            QRScannerView { code in
                guard let uuid = SpoolTagPayload.decodeQR(code) else {
                    notFound = true
                    return
                }
                var descriptor = FetchDescriptor<Spool>(predicate: #Predicate { $0.id == uuid })
                descriptor.fetchLimit = 1
                if let spool = try? context.fetch(descriptor).first {
                    scannedSpool = spool
                } else {
                    notFound = true
                }
            }
            .ignoresSafeArea()
            if notFound {
                VStack {
                    Spacer()
                    Text("QR code didn't match a spool in your inventory.")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PK.Radius.card))
                        .padding(.bottom, 60)
                }
            }
        }
        .navigationTitle("Scan QR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .navigationDestination(item: $scannedSpool) { SpoolDetailView(spool: $0) }
    }
}
