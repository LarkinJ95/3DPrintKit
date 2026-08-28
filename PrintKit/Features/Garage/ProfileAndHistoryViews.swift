import SwiftUI
import SwiftData
import Charts

// MARK: - Slicer profiles

struct ProfileListView: View {
    @Query(sort: \SlicerProfile.lastUsed, order: .reverse) private var profiles: [SlicerProfile]
    @State private var showAdd = false

    var body: some View {
        List {
            if profiles.isEmpty {
                PKEmptyState(symbol: "doc.text",
                             title: "No Slicer Profiles",
                             message: "Keep your tuned settings here — and mark the proven ones Known Good.",
                             actionTitle: "Add Profile") { showAdd = true }
            }
            ForEach(profiles) { profile in
                NavigationLink { ProfileDetailView(profile: profile) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(profile.name).font(.subheadline.weight(.medium))
                            if profile.isKnownGood {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption).foregroundStyle(.green)
                                    .accessibilityLabel("Known good profile")
                            }
                            if profile.isFavorite {
                                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                            }
                        }
                        Text([
                            profile.printer?.displayName,
                            MaterialLibrary.shared.material(for: profile.materialID)?.name,
                            "\(Int(profile.nozzleTemp)) °C"
                        ].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Slicer Profiles")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { NavigationStack { ProfileFormView(profile: nil) } }
    }
}

struct ProfileDetailView: View {
    @Bindable var profile: SlicerProfile
    @Environment(\.modelContext) private var context
    @State private var showEdit = false

    var body: some View {
        List {
            Section {
                HStack(spacing: PK.Spacing.sm) {
                    if profile.isKnownGood {
                        StatusBadge(status: .ready, text: "Known Good")
                    }
                    if let rate = profile.recordedSuccessRate {
                        StatusBadge(status: .info, text: Format.percent(rate * 100) + " success (\(profile.successCount + profile.failureCount) prints)")
                    }
                }
            }

            Section("Temperatures") {
                KeyValueRow(key: "Nozzle", value: "\(Int(profile.nozzleTemp)) °C")
                KeyValueRow(key: "Bed", value: "\(Int(profile.bedTemp)) °C")
                if profile.chamberTemp > 0 { KeyValueRow(key: "Chamber", value: "\(Int(profile.chamberTemp)) °C") }
            }
            Section("Speeds & Flow") {
                KeyValueRow(key: "Print speed", value: "\(Int(profile.printSpeed)) mm/s")
                if profile.wallSpeed > 0 { KeyValueRow(key: "Wall speed", value: "\(Int(profile.wallSpeed)) mm/s") }
                if profile.infillSpeed > 0 { KeyValueRow(key: "Infill speed", value: "\(Int(profile.infillSpeed)) mm/s") }
                if profile.volumetricLimit > 0 { KeyValueRow(key: "Volumetric limit", value: String(format: "%.1f mm³/s", profile.volumetricLimit)) }
                if profile.acceleration > 0 { KeyValueRow(key: "Acceleration", value: String(format: "%.0f mm/s²", profile.acceleration)) }
                KeyValueRow(key: "Flow ratio", value: String(format: "%.2f", profile.flowRatio))
                if profile.pressureAdvance > 0 { KeyValueRow(key: "Pressure advance", value: String(format: "%.3f", profile.pressureAdvance)) }
                KeyValueRow(key: "Retraction", value: String(format: "%.1f mm", profile.retractionMm))
                KeyValueRow(key: "Fan", value: "\(Int(profile.fanPercent))%")
            }
            Section("Geometry & Surface") {
                KeyValueRow(key: "Layer height", value: String(format: "%.2f mm", profile.layerHeight))
                KeyValueRow(key: "Line width", value: String(format: "%.2f mm", profile.lineWidth))
                KeyValueRow(key: "Nozzle", value: String(format: "%.2g mm", profile.nozzleDiameter))
                if !profile.bedSurface.isEmpty { KeyValueRow(key: "Bed surface", value: profile.bedSurface) }
                if !profile.adhesive.isEmpty { KeyValueRow(key: "Adhesive", value: profile.adhesive) }
                KeyValueRow(key: "Supports", value: profile.usesSupports ? "Yes" : "No")
            }
            if !profile.notes.isEmpty {
                Section("Notes") { Text(profile.notes).font(.subheadline) }
            }
            Section {
                Toggle("Known Good", isOn: $profile.isKnownGood)
                Toggle("Favorite", isOn: $profile.isFavorite)
                Button {
                    duplicateProfile()
                } label: {
                    Label("Duplicate Profile", systemImage: "plus.square.on.square")
                }
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) { NavigationStack { ProfileFormView(profile: profile) } }
    }

    private func duplicateProfile() {
        let copy = SlicerProfile()
        copy.name = profile.name + " Copy"
        copy.printer = profile.printer
        copy.plate = profile.plate
        copy.nozzleDiameter = profile.nozzleDiameter
        copy.materialID = profile.materialID
        copy.filamentProduct = profile.filamentProduct
        copy.layerHeight = profile.layerHeight
        copy.lineWidth = profile.lineWidth
        copy.nozzleTemp = profile.nozzleTemp
        copy.bedTemp = profile.bedTemp
        copy.chamberTemp = profile.chamberTemp
        copy.printSpeed = profile.printSpeed
        copy.wallSpeed = profile.wallSpeed
        copy.infillSpeed = profile.infillSpeed
        copy.volumetricLimit = profile.volumetricLimit
        copy.acceleration = profile.acceleration
        copy.retractionMm = profile.retractionMm
        copy.fanPercent = profile.fanPercent
        copy.flowRatio = profile.flowRatio
        copy.pressureAdvance = profile.pressureAdvance
        copy.usesSupports = profile.usesSupports
        copy.bedSurface = profile.bedSurface
        copy.adhesive = profile.adhesive
        copy.isKnownGood = false
        context.insert(copy)
        Haptics.success()
    }
}

struct ProfileFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var printers: [PrinterDevice]
    let profile: SlicerProfile?

    @State private var name = ""
    @State private var printer: PrinterDevice?
    @State private var materialID = "pla"
    @State private var filamentProduct = ""
    @State private var nozzleTemp = 210.0
    @State private var bedTemp = 60.0
    @State private var layerHeight = 0.2
    @State private var lineWidth = 0.42
    @State private var printSpeed = 50.0
    @State private var retraction = 0.8
    @State private var fan = 100.0
    @State private var flowRatio = 1.0
    @State private var pressureAdvance = 0.0
    @State private var nozzleDiameter = 0.4
    @State private var usesSupports = false
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Profile name", text: $name)
                Picker("Printer", selection: $printer) {
                    Text("None").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                Picker("Material", selection: $materialID) {
                    ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                }
                TextField("Filament product", text: $filamentProduct)
            }
            Section("Key Settings") {
                Stepper("Nozzle \(Int(nozzleTemp)) °C", value: $nozzleTemp, in: 150...350, step: 2)
                Stepper("Bed \(Int(bedTemp)) °C", value: $bedTemp, in: 0...140, step: 5)
                Stepper("Layer \(String(format: "%.2f", layerHeight)) mm", value: $layerHeight, in: 0.08...0.6, step: 0.04)
                Stepper("Line width \(String(format: "%.2f", lineWidth)) mm", value: $lineWidth, in: 0.1...2.0, step: 0.02)
                Stepper("Speed \(Int(printSpeed)) mm/s", value: $printSpeed, in: 5...600, step: 5)
                Stepper("Retraction \(String(format: "%.1f", retraction)) mm", value: $retraction, in: 0...10, step: 0.1)
                Stepper("Fan \(Int(fan))%", value: $fan, in: 0...100, step: 5)
                Stepper("Flow \(String(format: "%.2f", flowRatio))", value: $flowRatio, in: 0.8...1.2, step: 0.01)
                Stepper("Pressure advance \(String(format: "%.3f", pressureAdvance))", value: $pressureAdvance, in: 0...0.5, step: 0.002)
                Picker("Nozzle size", selection: $nozzleDiameter) {
                    ForEach([0.2, 0.4, 0.6, 0.8, 1.0], id: \.self) { Text(String(format: "%.2g mm", $0)).tag($0) }
                }
                Toggle("Supports", isOn: $usesSupports)
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
            }
        }
        .navigationTitle(profile == nil ? "New Profile" : "Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let profile else { return }
        name = profile.name
        printer = profile.printer
        materialID = profile.materialID
        filamentProduct = profile.filamentProduct
        nozzleTemp = profile.nozzleTemp
        bedTemp = profile.bedTemp
        layerHeight = profile.layerHeight
        lineWidth = profile.lineWidth
        printSpeed = profile.printSpeed
        retraction = profile.retractionMm
        fan = profile.fanPercent
        flowRatio = profile.flowRatio
        pressureAdvance = profile.pressureAdvance
        nozzleDiameter = profile.nozzleDiameter
        usesSupports = profile.usesSupports
        notes = profile.notes
    }

    private func save() {
        let target = profile ?? SlicerProfile()
        target.name = name
        target.printer = printer
        target.materialID = materialID
        target.filamentProduct = filamentProduct
        target.nozzleTemp = nozzleTemp
        target.bedTemp = bedTemp
        target.layerHeight = layerHeight
        target.lineWidth = lineWidth
        target.printSpeed = printSpeed
        target.retractionMm = retraction
        target.fanPercent = fan
        target.flowRatio = flowRatio
        target.pressureAdvance = pressureAdvance
        target.nozzleDiameter = nozzleDiameter
        target.usesSupports = usesSupports
        target.notes = notes
        if profile == nil { context.insert(target) }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Print history & stats

struct PrintHistoryView: View {
    @Query(sort: \PrintRecord.date, order: .reverse) private var prints: [PrintRecord]
    @State private var showLog = false

    private var totalHours: Double { prints.reduce(0) { $0 + $1.durationMinutes } / 60 }
    private var totalGrams: Double { prints.reduce(0) { $0 + $1.gramsUsed } }
    private var totalCost: Double { prints.reduce(0) { $0 + $1.cost } }
    private var successRate: Double {
        guard !prints.isEmpty else { return 0 }
        return Double(prints.filter(\.success).count) / Double(prints.count) * 100
    }
    private var wasteGrams: Double { prints.filter { $0.category.isWaste }.reduce(0) { $0 + $1.gramsUsed } }

    private var monthlyUsage: [(month: String, grams: Double)] {
        var buckets: [String: Double] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        for print in prints {
            buckets[formatter.string(from: print.date), default: 0] += print.gramsUsed
        }
        return buckets.sorted { $0.key < $1.key }.suffix(6).map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            if !prints.isEmpty {
                Section("Statistics") {
                    HStack(spacing: PK.Spacing.xl) {
                        MetricView(label: "Hours", value: String(format: "%.0f", totalHours))
                        MetricView(label: "Filament", value: Format.grams(totalGrams))
                        MetricView(label: "Success", value: Format.percent(successRate))
                    }
                    HStack(spacing: PK.Spacing.xl) {
                        MetricView(label: "Cost", value: Format.currency(totalCost))
                        MetricView(label: "Waste", value: Format.grams(wasteGrams))
                        MetricView(label: "Waste rate", value: totalGrams > 0 ? Format.percent(wasteGrams / totalGrams * 100) : "—")
                    }
                }
                Section("Monthly Filament Use") {
                    Chart(monthlyUsage, id: \.month) { item in
                        BarMark(x: .value("Month", item.month), y: .value("Grams", item.grams))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 160)
                    .accessibilityLabel("Monthly filament usage chart")
                }
            }
            Section("History") {
                if prints.isEmpty {
                    PKEmptyState(symbol: "printer", title: "No Prints Logged",
                                 message: "Log prints to build statistics, waste tracking, and personal knowledge.",
                                 actionTitle: "Log Print") { showLog = true }
                }
                ForEach(prints) { record in
                    HStack {
                        Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(record.success ? Color.green : Color.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.name.isEmpty ? record.category.rawValue : record.name).font(.subheadline.weight(.medium))
                            Text([
                                record.printer?.displayName,
                                record.spool?.displayName,
                                Format.dateTime(record.date)
                            ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.grams(record.gramsUsed)).font(.subheadline.monospacedDigit())
                            Text(Format.duration(minutes: record.durationMinutes)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Print History")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showLog = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showLog) { NavigationStack { PrintLogFormView(record: nil) } }
    }
}

struct PrintLogFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var printers: [PrinterDevice]
    @Query private var spools: [Spool]
    @Query private var profiles: [SlicerProfile]
    @Query private var projects: [ProjectItem]

    let record: PrintRecord?

    @State private var name = ""
    @State private var printer: PrinterDevice?
    @State private var spool: Spool?
    @State private var profile: SlicerProfile?
    @State private var project: ProjectItem?
    @State private var minutes = 60.0
    @State private var grams = 0.0
    @State private var success = true
    @State private var category = PrintOutcomeCategory.finalPart
    @State private var cost = 0.0
    @State private var failureCategory = ""
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Print") {
                TextField("Name", text: $name)
                Picker("Printer", selection: $printer) {
                    Text("None").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                Picker("Spool", selection: $spool) {
                    Text("None").tag(Spool?.none)
                    ForEach(spools.filter { !$0.isArchived }) { Text($0.displayName).tag(Spool?.some($0)) }
                }
                Picker("Profile", selection: $profile) {
                    Text("None").tag(SlicerProfile?.none)
                    ForEach(profiles) { Text($0.name).tag(SlicerProfile?.some($0)) }
                }
                Picker("Project", selection: $project) {
                    Text("None").tag(ProjectItem?.none)
                    ForEach(projects) { Text($0.name).tag(ProjectItem?.some($0)) }
                }
            }
            Section("Outcome") {
                HStack { Text("Duration (min)"); Spacer(); TextField("0", value: $minutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Filament used (g)"); Spacer(); TextField("0", value: $grams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                Picker("Category", selection: $category) {
                    ForEach(PrintOutcomeCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Successful", isOn: $success)
                if !success {
                    TextField("Failure category (e.g. warping)", text: $failureCategory)
                }
                HStack { Text("Cost"); Spacer(); TextField("0.00", value: $cost, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
            }
        }
        .navigationTitle(record == nil ? "Log Print" : "Edit Print")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
    }

    private func save() {
        let target = record ?? PrintRecord()
        target.name = name
        target.printer = printer
        target.spool = spool
        target.profile = profile
        target.project = project
        target.materialID = spool?.materialID ?? ""
        target.durationMinutes = minutes
        target.gramsUsed = grams
        target.success = success
        target.category = category
        target.failureCategory = failureCategory
        target.cost = cost
        target.notes = notes

        if record == nil {
            context.insert(target)
            // Deduct filament and accumulate printer hours.
            if let spool, grams > 0 {
                spool.currentWeightG = max(spool.currentWeightG - grams, 0)
                spool.lastUsedDate = Date()
                SyncEngine.shared.enqueue(.init(id: UUID(), kind: .filamentDelta, entity: "spools",
                                                recordID: spool.id, payload: nil, deltaGrams: -grams, queuedAt: Date()))
            }
            if let printer {
                printer.totalPrintHours += minutes / 60
            }
            if let profile {
                profile.lastUsed = Date()
                if success { profile.successCount += 1 } else { profile.failureCount += 1 }
            }
            // Log a failure journal stub automatically for failed prints.
            if !success {
                let failure = FailureReport()
                failure.printer = printer
                failure.spool = spool
                failure.profile = profile
                failure.category = failureCategory.isEmpty ? "Unspecified" : failureCategory
                failure.settingsSummary = profile.map { "\(Int($0.nozzleTemp)) °C · \(String(format: "%.2g", $0.nozzleDiameter)) mm · \(Int($0.printSpeed)) mm/s" } ?? ""
                context.insert(failure)
            }
        }
        Haptics.success()
        dismiss()
    }
}
