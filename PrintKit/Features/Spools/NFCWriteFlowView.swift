import SwiftUI
import SwiftData

/// NFC write workflow:
/// Select Spool → Review Tag Data → Scan Writable Tag → Verify Compatibility
/// → Write → Read Back → Verify → Success
struct NFCWriteFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var spools: [Spool]

    var prefilledSpool: Spool? = nil

    enum Step: Int {
        case selectSpool, review, scan, done
    }

    @State private var step: Step = .selectSpool
    @State private var spool: Spool?
    @State private var nfc = NFCManager()
    @State private var verified = false

    var body: some View {
        Group {
            switch step {
            case .selectSpool:
                List(spools.filter { !$0.isArchived }) { candidate in
                    Button {
                        spool = candidate
                        step = .review
                    } label: {
                        SpoolRowView(spool: candidate)
                    }
                }
                .overlay {
                    if spools.isEmpty {
                        PKEmptyState(symbol: "circle.dashed", title: "No Spools",
                                     message: "Add a spool before writing a tag.")
                    }
                }
                .navigationTitle("Select Spool")

            case .review:
                if let spool {
                    Form {
                        Section("Tag Data") {
                            KeyValueRow(key: "Schema", value: "printkit.spool · v1")
                            KeyValueRow(key: "Spool ID", value: String(spool.id.uuidString.prefix(8)))
                            KeyValueRow(key: "Manufacturer", value: spool.manufacturer.isEmpty ? "—" : spool.manufacturer)
                            KeyValueRow(key: "Material", value: MaterialLibrary.shared.material(for: spool.materialID)?.name ?? spool.materialID)
                            KeyValueRow(key: "Color", value: spool.colorName.isEmpty ? "—" : spool.colorName)
                            KeyValueRow(key: "Original", value: Format.grams(spool.originalNetWeightG))
                            KeyValueRow(key: "Remaining", value: Format.grams(spool.currentWeightG))
                        }
                        Section {
                            let size = (try? SpoolTagPayload(spool: spool).encode().count) ?? 0
                            KeyValueRow(key: "Payload size", value: "\(size) bytes")
                            Text("Requires a writable NDEF tag (NTAG213 or larger recommended). The tag is written, then read back and verified.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Review Tag Data")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Write Tag") {
                                step = .scan
                            }
                        }
                    }
                }

            case .scan:
                VStack(spacing: PK.Spacing.xl) {
                    Spacer()
                    Image(systemName: symbolForState)
                        .font(.system(size: 72))
                        .foregroundStyle(colorForState)
                        .symbolEffect(.pulse, isActive: nfc.state == .ready)
                    VStack(spacing: PK.Spacing.sm) {
                        Text(titleForState).font(.title3.weight(.semibold))
                        Text(subtitleForState).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        if !nfc.tagInfo.isEmpty {
                            Text(nfc.tagInfo).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if case .failed = nfc.state {
                        Button("Try Again") { startWrite() }
                            .buttonStyle(.borderedProminent)
                            .padding(.bottom)
                    }
                }
                .navigationTitle("Write NFC Tag")
                .onAppear(perform: startWrite)
                .onDisappear { nfc.cancel() }

            case .done:
                VStack(spacing: PK.Spacing.lg) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: step)
                    Text("Tag Written & Verified").font(.title3.weight(.semibold))
                    Text("The tag now opens this spool when scanned.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Success")
            }
        }
        .onAppear {
            if let prefilledSpool {
                spool = prefilledSpool
                step = .review
            }
        }
    }

    private var symbolForState: String {
        switch nfc.state {
        case .complete: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .writing: return "pencil.circle"
        case .verifying: return "magnifyingglass.circle"
        default: return "wave.3.right.circle"
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
        case .ready: return "Scan Writable Tag"
        case .detected: return "Tag Detected"
        case .writing: return "Writing…"
        case .verifying: return "Reading Back…"
        case .complete: return "Verified"
        case .failed: return "Write Failed"
        case .idle: return "Preparing…"
        case .reading: return "Reading…"
        }
    }

    private var subtitleForState: String {
        switch nfc.state {
        case .ready: return "Hold the top of your iPhone near the tag."
        case .failed(let message): return message
        case .verifying: return "Don't move the tag away."
        default: return ""
        }
    }

    private func startWrite() {
        guard let spool else { return }
        nfc.onWriteComplete = { success in
            if success {
                spool.nfcTagWritten = true
                try? context.save()
                step = .done
            }
        }
        nfc.begin(mode: .writeSpool(spool))
    }
}
