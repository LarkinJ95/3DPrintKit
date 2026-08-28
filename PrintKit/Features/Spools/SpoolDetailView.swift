import SwiftUI
import SwiftData

struct SpoolDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Bindable var spool: Spool

    @Query private var allSessions: [DryingSession]
    @Query private var allPrints: [PrintRecord]
    @Query private var allTransfers: [FilamentTransfer]
    @Query private var allProfiles: [SlicerProfile]

    @State private var showEdit = false
    @State private var showQR = false
    @State private var showLabels = false
    @State private var showNFCWrite = false
    @State private var showLogUse = false
    @State private var gramsUsed: Double = 0

    private var material: FilamentMaterial? {
        MaterialLibrary.shared.material(for: spool.materialID)
    }

    private var dryingHistory: [DryingSession] {
        allSessions.filter { $0.spool?.id == spool.id }.sorted { $0.startedAt > $1.startedAt }
    }

    private var prints: [PrintRecord] {
        allPrints.filter { $0.spool?.id == spool.id }.sorted { $0.date > $1.date }
    }

    private var transfers: [FilamentTransfer] {
        allTransfers.filter { $0.sourceSpool?.id == spool.id || $0.destinationSpool?.id == spool.id }
            .sorted { $0.date > $1.date }
    }

    private var knownGoodProfiles: [SlicerProfile] {
        allProfiles.filter { $0.isKnownGood && ($0.materialID == spool.materialID || $0.filamentProduct == spool.productLine) }
    }

    var body: some View {
        List {
            // MARK: Spool visualization
            Section {
                VStack(spacing: PK.Spacing.lg) {
                    ZStack {
                        SpoolRingView(fraction: spool.remainingFraction, filamentColor: spool.color, lineWidth: 20)
                        VStack(spacing: 2) {
                            Text(Format.percent(spool.remainingPercent))
                                .font(.title.weight(.bold)).monospacedDigit()
                            Text("remaining")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 210)
                    .padding(.top, 8)

                    HStack(spacing: PK.Spacing.xl) {
                        MetricView(label: "Weight", value: Format.grams(spool.currentWeightG))
                        if let material {
                            MetricView(label: "Length",
                                       value: Format.length(meters: spool.estimatedLengthMeters(density: material.density)))
                        }
                        if let perKg = spool.costPerKg {
                            MetricView(label: "Cost/kg", value: Format.currency(perKg))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Quick use logging
                    HStack {
                        TextField("Grams used", value: $gramsUsed, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Button("Log Use") {
                            guard gramsUsed > 0 else { return }
                            spool.currentWeightG = max(spool.currentWeightG - gramsUsed, 0)
                            spool.lastUsedDate = Date()
                            SyncEngine.shared.enqueue(.init(id: UUID(), kind: .filamentDelta, entity: "spools",
                                                            recordID: spool.id, payload: nil,
                                                            deltaGrams: -gramsUsed, queuedAt: Date()))
                            gramsUsed = 0
                            Haptics.success()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(gramsUsed <= 0)
                    }
                }
                .listRowBackground(Color.clear)
            }

            // MARK: Status
            Section("Status") {
                let status = spool.status(dryingActive: dryingHistory.contains(where: \.isActive))
                HStack {
                    Text("Status").foregroundStyle(.secondary)
                    Spacer()
                    StatusBadge(status: status.status, text: status.rawValue)
                }
                KeyValueRow(key: "NFC Tag", value: spool.nfcTagWritten ? "Written" : "Not written")
                KeyValueRow(key: "QR", value: "Available")
                if !spool.amsSlotLabel.isEmpty {
                    KeyValueRow(key: "AMS/MMU", value: spool.amsSlotLabel)
                }
            }

            // MARK: Identity
            Section("Identity") {
                KeyValueRow(key: "Manufacturer", value: spool.manufacturer.isEmpty ? "—" : spool.manufacturer)
                KeyValueRow(key: "Product", value: spool.productLine.isEmpty ? "—" : spool.productLine)
                KeyValueRow(key: "Material", value: material.map { "\($0.name) (\($0.family))" } ?? spool.materialID)
                KeyValueRow(key: "Color", value: spool.colorName.isEmpty ? "—" : spool.colorName)
                KeyValueRow(key: "Finish", value: spool.finish.displayName)
                KeyValueRow(key: "Diameter", value: String(format: "%.2f mm", spool.diameter))
                if !spool.lotNumber.isEmpty { KeyValueRow(key: "Lot", value: spool.lotNumber) }
                if !spool.batchNumber.isEmpty { KeyValueRow(key: "Batch", value: spool.batchNumber) }
                KeyValueRow(key: "Spool ID", value: String(spool.id.uuidString.prefix(8)))
            }

            // MARK: Weight & cost
            Section("Weight & Cost") {
                KeyValueRow(key: "Original net", value: Format.grams(spool.originalNetWeightG))
                KeyValueRow(key: "Empty spool", value: Format.grams(spool.emptySpoolWeightG))
                KeyValueRow(key: "Current est.", value: Format.grams(spool.currentWeightG))
                if spool.cost > 0 {
                    KeyValueRow(key: "Paid", value: Format.currency(spool.cost))
                }
                if !spool.vendor.isEmpty { KeyValueRow(key: "Vendor", value: spool.vendor) }
            }

            // MARK: Dates & storage
            Section("Dates & Storage") {
                KeyValueRow(key: "Purchased", value: Format.date(spool.purchaseDate))
                KeyValueRow(key: "Opened", value: Format.date(spool.openedDate))
                KeyValueRow(key: "Last used", value: Format.date(spool.lastUsedDate))
                KeyValueRow(key: "Last dried", value: Format.date(spool.lastDriedDate))
                if let location = spool.storageLocation {
                    KeyValueRow(key: "Location", value: location.name)
                }
            }

            // MARK: Drying
            Section {
                NavigationLink {
                    DryingStartView(prefilledSpool: spool)
                } label: {
                    Label("Start Drying", systemImage: "humidity")
                }
                if spool.needsDrying {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("This material is moisture-sensitive and was last dried \(Format.date(spool.lastDriedDate ?? spool.openedDate)).")
                            .font(.caption)
                    }
                }
                ForEach(dryingHistory.prefix(5)) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(session.targetTempC)) °C · \(Format.duration(minutes: session.actualMinutes ?? session.plannedMinutes))")
                                .font(.subheadline)
                            Text(Format.dateTime(session.startedAt))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: session.isActive ? .info : .ready,
                                    text: session.isActive ? "Active" : "Done")
                    }
                }
            } header: {
                Text("Drying")
            } footer: {
                if let material {
                    Text("Reference guidance for \(material.name): \(material.dryTemp) °C for \(material.dryHours)h. Manufacturer instructions take precedence.")
                        .font(.caption)
                }
            }

            // MARK: Printing
            Section("Printing Reference") {
                if let material {
                    KeyValueRow(key: "Nozzle", value: material.nozzleRangeText, source: .reference)
                    KeyValueRow(key: "Bed", value: material.bedRangeText, source: .reference)
                    KeyValueRow(key: "Dry", value: "\(material.dryTemp) °C · \(material.dryHours)h", source: .reference)
                    NavigationLink {
                        MaterialDetailView(material: material)
                    } label: {
                        Label("Full material reference", systemImage: "book")
                    }
                }
                if !knownGoodProfiles.isEmpty {
                    ForEach(knownGoodProfiles) { profile in
                        NavigationLink {
                            ProfileDetailView(profile: profile)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).font(.subheadline)
                                    Text("\(profile.successCount) successful prints on record")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            // MARK: Genealogy
            Section("History from This Spool") {
                if prints.isEmpty && transfers.isEmpty {
                    Text("No prints or transfers recorded yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(prints) { record in
                    HStack {
                        Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(record.success ? Color.green : Color.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.name.isEmpty ? record.category.rawValue : record.name).font(.subheadline)
                            Text("\(Format.date(record.date)) · \(Format.grams(record.gramsUsed))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                ForEach(transfers) { transfer in
                    HStack {
                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            let outgoing = transfer.sourceSpool?.id == spool.id
                            Text(outgoing
                                 ? "Moved \(Format.grams(transfer.grams)) to \(transfer.destinationSpool?.displayName ?? "another spool")"
                                 : "Received \(Format.grams(transfer.grams)) from \(transfer.sourceSpool?.displayName ?? "another spool")")
                                .font(.subheadline)
                            Text(Format.date(transfer.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: Lot quality
            if spool.lotFlagged || !spool.lotNotes.isEmpty {
                Section("Lot / Batch Notes") {
                    if spool.lotFlagged {
                        Label("This lot is flagged for quality concerns.", systemImage: "flag.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(spool.lotNotes).font(.subheadline)
                }
            }

            // MARK: Photos & notes
            Section("Photos") {
                PhotoStripView(photoDatas: $spool.photoDatas)
            }
            Section("Notes") {
                TextEditor(text: $spool.notes)
                    .frame(minHeight: 70)
            }
        }
        .navigationTitle(spool.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showQR = true } label: { Label("Show QR Code", systemImage: "qrcode") }
                    Button { showLabels = true } label: { Label("Print Label", systemImage: "printer") }
                    Button { showNFCWrite = true } label: { Label("Write NFC Tag", systemImage: "wave.3.right") }
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Divider()
                    ShareLink(item: "printkit://spool/\(spool.id.uuidString)", subject: Text(spool.displayName))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack { SpoolFormView(spool: spool) }
        }
        .sheet(isPresented: $showQR) {
            NavigationStack { SpoolQRView(spool: spool) }
        }
        .sheet(isPresented: $showLabels) {
            NavigationStack { LabelGeneratorView(spool: spool) }
        }
        .sheet(isPresented: $showNFCWrite) {
            NavigationStack { NFCWriteFlowView(prefilledSpool: spool) }
        }
    }
}

struct SpoolQRView: View {
    let spool: Spool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: PK.Spacing.xl) {
            Spacer()
            QRCodeView(content: SpoolTagPayload(spool: spool).qrString)
                .frame(width: 240, height: 240)
                .padding()
                .background(Color.white, in: RoundedRectangle(cornerRadius: PK.Radius.card))
            VStack(spacing: 4) {
                Text(spool.displayName).font(.headline)
                Text("ID \(String(spool.id.uuidString.prefix(8)))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ShareLink(item: Image(uiImage: QRCodeGenerator.image(from: SpoolTagPayload(spool: spool).qrString) ?? UIImage()),
                      preview: SharePreview("Spool QR", image: Image(systemName: "qrcode"))) {
                Label("Share QR Image", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .navigationTitle("Spool QR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
}
