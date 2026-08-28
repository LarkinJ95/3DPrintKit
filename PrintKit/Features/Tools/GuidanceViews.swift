import SwiftUI
import SwiftData

// MARK: - Tolerance library

struct ToleranceLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ToleranceEntry.date, order: .reverse) private var entries: [ToleranceEntry]
    @Query private var printers: [PrinterDevice]
    @State private var showAdd = false

    var body: some View {
        List {
            if entries.isEmpty {
                PKEmptyState(symbol: "ruler",
                             title: "No Tested Fits Yet",
                             message: "Save the clearances you measure (slip, press, snap fits…) so you stop re-testing them.",
                             actionTitle: "Add Tested Fit") { showAdd = true }
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.category.displayName).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(String(format: "%.2f mm", entry.clearanceMm))
                            .font(.subheadline.monospacedDigit())
                    }
                    Text([
                        entry.printer?.displayName,
                        MaterialLibrary.shared.material(for: entry.materialID)?.name,
                        String(format: "%.2g mm nozzle", entry.nozzleDiameter),
                        entry.orientation.displayName
                    ].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                    if !entry.notes.isEmpty {
                        Text(entry.notes).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { indexSet in
                for index in indexSet { context.delete(entries[index]) }
            }
        }
        .navigationTitle("Tolerance Library")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { NavigationStack { ToleranceFormView() } }
    }
}

struct ToleranceFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var printers: [PrinterDevice]
    @State private var category = FitCategory.snugFit
    @State private var clearance = 0.2
    @State private var printer: PrinterDevice?
    @State private var materialID = "pla"
    @State private var nozzleDiameter = 0.4
    @State private var layerHeight = 0.2
    @State private var orientation = PartOrientation.horizontal
    @State private var notes = ""

    var body: some View {
        Form {
            Picker("Fit type", selection: $category) {
                ForEach(FitCategory.allCases) { Text($0.displayName).tag($0) }
            }
            Stepper(value: $clearance, in: -0.5...2.0, step: 0.02) {
                HStack { Text("Clearance"); Spacer(); Text(String(format: "%.2f mm", clearance)).monospacedDigit() }
            }
            Picker("Printer", selection: $printer) {
                Text("None").tag(PrinterDevice?.none)
                ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
            }
            Picker("Material", selection: $materialID) {
                ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
            }
            Stepper("Nozzle \(String(format: "%.2g", nozzleDiameter)) mm", value: $nozzleDiameter, in: 0.2...1.2, step: 0.2)
            Stepper("Layer \(String(format: "%.2f", layerHeight)) mm", value: $layerHeight, in: 0.08...0.6, step: 0.04)
            Picker("Orientation", selection: $orientation) {
                ForEach(PartOrientation.allCases) { Text($0.displayName).tag($0) }
            }
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
        }
        .navigationTitle("Tested Fit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let entry = ToleranceEntry()
                    entry.category = category
                    entry.clearanceMm = clearance
                    entry.printer = printer
                    entry.materialID = materialID
                    entry.nozzleDiameter = nozzleDiameter
                    entry.layerHeight = layerHeight
                    entry.orientation = orientation
                    entry.notes = notes
                    context.insert(entry)
                    Haptics.success()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Fastener & thread reference

struct FastenerReferenceView: View {
    var body: some View {
        List {
            Section {
                Text("Generic workshop reference values for printed parts — verify against the fastener or insert manufacturer's specification when available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Metric Screws (mm)") {
                ForEach(FastenerReference.metric) { row in
                    DisclosureGroup(row.designation) {
                        KeyValueRow(key: "Clearance (close)", value: row.clearanceClose.map { String(format: "%.1f", $0) } ?? "—", source: .reference)
                        KeyValueRow(key: "Clearance (normal)", value: row.clearanceNormal.map { String(format: "%.1f", $0) } ?? "—", source: .reference)
                        KeyValueRow(key: "Clearance (loose)", value: row.clearanceLoose.map { String(format: "%.1f", $0) } ?? "—", source: .reference)
                        KeyValueRow(key: "Pilot hole", value: row.pilotHole.map { String(format: "%.1f", $0) } ?? "—", source: .reference)
                        KeyValueRow(key: "Heat-set insert hole", value: row.insertHole.map { String(format: "%.1f", $0) } ?? "—", source: .reference)
                        if !row.notes.isEmpty {
                            Text(row.notes).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Imperial Screws (mm)") {
                ForEach(FastenerReference.imperial) { row in
                    DisclosureGroup(row.designation) {
                        KeyValueRow(key: "Clearance (normal)", value: row.clearanceNormal.map { String(format: "%.1f", $0) } ?? "—", source: .reference)
                        KeyValueRow(key: "Pilot hole", value: row.pilotHole.map { String(format: "%.1f", $0) } ?? "—", source: .reference)
                        KeyValueRow(key: "Insert hole", value: row.insertHole.map { String(format: "%.1f", $0) } ?? "—", source: .reference)
                    }
                }
            }
            Section("Bearings") {
                ForEach(FastenerReference.bearings) { row in
                    KeyValueRow(key: row.designation,
                                value: String(format: "bore %.1f mm → model %.2f mm", row.boreMM, row.suggestedBore),
                                source: .reference)
                }
            }
        }
        .navigationTitle("Fasteners")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ThreadReferenceView: View {
    var body: some View {
        List {
            ForEach(ThreadReference.entries) { entry in
                Section(entry.title) {
                    Text(entry.body)
                        .font(.subheadline)
                    HStack {
                        Spacer()
                        SourceTag(source: .reference)
                    }
                }
            }
            Section {
                NavigationLink { ToleranceLibraryView() } label: {
                    Label("Your Tested Values (Tolerance Library)", systemImage: "ruler")
                }
            }
        }
        .navigationTitle("Threads & Inserts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Calibration center

struct CalibrationListView: View {
    @Query(sort: \CalibrationRecord.date, order: .reverse) private var records: [CalibrationRecord]

    var body: some View {
        List {
            Section("Guided Workflows") {
                ForEach(CalibrationLibrary.guides) { guide in
                    NavigationLink {
                        CalibrationDetailView(guide: guide)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(guide.title).font(.subheadline.weight(.medium))
                            Text(guide.purpose).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if !records.isEmpty {
                Section("Saved Results") {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(CalibrationLibrary.guide(for: record.typeKey)?.title ?? record.typeKey)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                SourceTag(source: .personal)
                            }
                            if !record.resultSummary.isEmpty {
                                Text(record.resultSummary).font(.caption.monospacedDigit())
                            }
                            Text([
                                record.printer?.displayName,
                                MaterialLibrary.shared.material(for: record.materialID)?.name,
                                Format.date(record.date)
                            ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Calibration")
    }
}

struct CalibrationDetailView: View {
    let guide: CalibrationGuide
    @Environment(\.modelContext) private var context
    @Query private var printers: [PrinterDevice]

    @State private var printer: PrinterDevice?
    @State private var materialID = "pla"
    @State private var numericResult = 0.0
    @State private var summary = ""
    @State private var notes = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Purpose") {
                Text(guide.purpose).font(.subheadline)
            }
            Section("Symptoms") {
                Text(guide.symptoms).font(.subheadline)
            }
            Section("Procedure") {
                ForEach(Array(guide.procedure.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: PK.Spacing.sm) {
                        Text("\(index + 1).")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(step).font(.subheadline)
                    }
                }
            }
            Section("Measurement") {
                Text(guide.measurement).font(.subheadline)
            }
            Section("Interpretation") {
                Text(guide.interpretation).font(.subheadline)
            }
            Section("Recommended Next Step") {
                Text(guide.nextStep).font(.subheadline)
            }
            Section("Save Result") {
                Picker("Printer", selection: $printer) {
                    Text("None").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                Picker("Material", selection: $materialID) {
                    ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                }
                if let unit = guide.resultUnit {
                    HStack {
                        Text("Result")
                        Spacer()
                        TextField("0", value: $numericResult, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                        Text(unit).foregroundStyle(.secondary)
                    }
                }
                TextField("Summary (e.g. best at 242 °C)", text: $summary)
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                Button(saved ? "Saved ✓" : "Save Calibration Result") {
                    let record = CalibrationRecord()
                    record.typeKey = guide.id
                    record.printer = printer
                    record.materialID = materialID
                    record.numericResult = guide.resultUnit == nil ? nil : numericResult
                    record.resultSummary = summary
                    record.notes = notes
                    context.insert(record)
                    Haptics.success()
                    saved = true
                }
                .disabled(saved)
            }
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Troubleshooting

struct TroubleshootListView: View {
    @State private var search = ""

    private var issues: [TroubleshootingIssue] {
        if search.isEmpty { return TroubleshootingLibrary.issues }
        return TroubleshootingLibrary.issues.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.symptoms.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List(issues) { issue in
            NavigationLink {
                TroubleshootDetailView(issue: issue)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title).font(.subheadline.weight(.medium))
                    Text(issue.symptoms).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.vertical, 2)
            }
        }
        .searchable(text: $search, prompt: "Describe the problem")
        .navigationTitle("Troubleshooting")
    }
}

struct TroubleshootDetailView: View {
    let issue: TroubleshootingIssue
    @Query private var printers: [PrinterDevice]
    @Query private var failures: [FailureReport]

    /// Historical fix for this printer+category — personal knowledge surfacing.
    private var pastFix: FailureReport? {
        failures.first { !$0.finalSolution.isEmpty && $0.category.localizedCaseInsensitiveContains(issue.title.components(separatedBy: " ").first ?? "") }
    }

    var body: some View {
        List {
            Section("Symptoms") {
                Text(issue.symptoms).font(.subheadline)
            }
            if let pastFix {
                Section {
                    Label("Last time, this fixed it:", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.yellow)
                    Text(pastFix.finalSolution).font(.subheadline)
                    Text("From your failure journal on \(Format.date(pastFix.date)) — your history, not a universal rule.")
                        .font(.caption2).foregroundStyle(.tertiary)
                } header: {
                    Text("From Your History")
                }
            }
            Section("Check First") {
                ForEach(issue.questions, id: \.self) { question in
                    Label(question, systemImage: "questionmark.circle")
                        .font(.subheadline)
                }
            }
            Section("Likely Causes (ranked, not certain)") {
                ForEach(issue.causes.sorted { $0.likelihood > $1.likelihood }) { cause in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(cause.cause).font(.subheadline.weight(.medium))
                            Spacer()
                            RatingBar(value: cause.likelihood)
                        }
                        Text(cause.fix).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(cause.cause), likelihood \(cause.likelihood) of 5. \(cause.fix)")
                }
            }
        }
        .navigationTitle(issue.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - NFC utilities

struct NFCUtilitiesView: View {
    @State private var nfc = NFCManager()
    @State private var textToWrite = ""
    @State private var urlToWrite = "printkit://home"
    @State private var showLockConfirm = false
    @State private var showEraseConfirm = false

    var body: some View {
        List {
            if !NFCManager.isAvailable {
                Section {
                    Label("NFC is not available on this device (e.g. Simulator). All tag tools require a physical iPhone.",
                          systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section("Read") {
                Button {
                    nfc.begin(mode: .readUtility)
                } label: {
                    Label("Read Any NDEF Tag", systemImage: "wave.3.right.circle")
                }
                .disabled(!NFCManager.isAvailable)
                if !nfc.tagInfo.isEmpty {
                    KeyValueRow(key: "Tag", value: nfc.tagInfo)
                }
                ForEach(nfc.utilityRecords, id: \.self) { record in
                    Text(record).font(.caption.monospaced())
                }
            }

            Section("Write") {
                HStack {
                    TextField("Text to write", text: $textToWrite)
                    Button("Write") { nfc.begin(mode: .writeText(textToWrite)) }
                        .disabled(textToWrite.isEmpty || !NFCManager.isAvailable)
                }
                HStack {
                    TextField("URL to write", text: $urlToWrite)
                        .keyboardType(.URL)
                    Button("Write") { nfc.begin(mode: .writeURL(urlToWrite)) }
                        .disabled(urlToWrite.isEmpty || !NFCManager.isAvailable)
                }
                NavigationLink {
                    NFCWriteFlowView()
                } label: {
                    Label("Write 3DPrintKit Spool Record", systemImage: "pencil.and.radiowaves.left.and.right")
                }
            }

            Section("Maintenance") {
                Button(role: .destructive) {
                    showEraseConfirm = true
                } label: {
                    Label("Erase Tag", systemImage: "eraser")
                }
                .disabled(!NFCManager.isAvailable)

                Button(role: .destructive) {
                    showLockConfirm = true
                } label: {
                    Label("Lock Tag Permanently", systemImage: "lock.fill")
                }
                .disabled(!NFCManager.isAvailable)
            }

            if case .failed(let message) = nfc.state {
                Section {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("NFC Utilities")
        .alert("Erase Tag?", isPresented: $showEraseConfirm) {
            Button("Erase", role: .destructive) { nfc.begin(mode: .erase) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The NDEF content on the tag will be removed. 3DPrintKit spools linked to the tag will no longer open when scanned until you write the tag again.")
        }
        .alert("Permanently Lock Tag?", isPresented: $showLockConfirm) {
            Button("Lock Permanently", role: .destructive) { nfc.begin(mode: .lock) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Locking is IRREVERSIBLE. The tag becomes read-only forever and can never be rewritten or erased. Only lock a tag whose contents are final.")
        }
    }
}
