import SwiftUI
import SwiftData

// MARK: - Scale-based filament calculator

struct ScaleCalculatorView: View {
    @State private var gross = 900.0
    @State private var emptySpool = 140.0
    @State private var diameter = 1.75
    @State private var materialID = "pla"

    private var material: FilamentMaterial? { MaterialLibrary.shared.material(for: materialID) }
    private var netG: Double { FilamentMath.netGrams(grossGrams: gross, emptySpoolGrams: emptySpool) }

    var body: some View {
        Form {
            Section("Scale Reading") {
                HStack { Text("Gross weight"); Spacer(); TextField("g", value: $gross, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100); Text("g").foregroundStyle(.secondary) }
                HStack { Text("Empty spool"); Spacer(); TextField("g", value: $emptySpool, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100); Text("g").foregroundStyle(.secondary) }
                Picker("Diameter", selection: $diameter) {
                    Text("1.75 mm").tag(1.75); Text("2.85 mm").tag(2.85)
                }
                Picker("Material", selection: $materialID) {
                    ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                }
            }
            Section("Result") {
                KeyValueRow(key: "Remaining", value: Format.grams(netG))
                if let material {
                    KeyValueRow(key: "Percent of 1 kg", value: Format.percent(netG / 1000 * 100))
                    KeyValueRow(key: "Volume", value: String(format: "%.1f cm³", FilamentMath.volumeCM3(grams: netG, densityGcm3: material.density)))
                    KeyValueRow(key: "Estimated length", value: Format.length(meters: FilamentMath.gramsToMeters(netG, diameterMM: diameter, densityGcm3: material.density)))
                }
            }
        }
        .navigationTitle("Scale Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Length / weight converter

struct ConverterView: View {
    enum Unit: String, CaseIterable, Identifiable {
        case grams, kilograms, meters, feet, volume, percentOfSpool
        var id: String { rawValue }
        var label: String {
            switch self {
            case .grams: return "grams"
            case .kilograms: return "kg"
            case .meters: return "meters"
            case .feet: return "feet"
            case .volume: return "cm³"
            case .percentOfSpool: return "% of spool"
            }
        }
    }

    @State private var inputUnit: Unit = .grams
    @State private var inputValue = 100.0
    @State private var diameter = 1.75
    @State private var materialID = "pla"
    @State private var spoolSize = 1000.0

    private var density: Double { MaterialLibrary.shared.material(for: materialID)?.density ?? 1.24 }

    private var grams: Double {
        switch inputUnit {
        case .grams: return inputValue
        case .kilograms: return inputValue * 1000
        case .meters: return FilamentMath.metersToGrams(inputValue, diameterMM: diameter, densityGcm3: density)
        case .feet: return FilamentMath.metersToGrams(inputValue / 3.28084, diameterMM: diameter, densityGcm3: density)
        case .volume: return inputValue * density
        case .percentOfSpool: return spoolSize * inputValue / 100
        }
    }

    var body: some View {
        Form {
            Section("Input") {
                HStack {
                    TextField("Value", value: $inputValue, format: .number).keyboardType(.decimalPad)
                    Picker("Unit", selection: $inputUnit) {
                        ForEach(Unit.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                Picker("Diameter", selection: $diameter) {
                    Text("1.75 mm").tag(1.75); Text("2.85 mm").tag(2.85)
                }
                Picker("Material", selection: $materialID) {
                    ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                }
                if inputUnit == .percentOfSpool {
                    Stepper("Spool size \(Format.grams(spoolSize))", value: $spoolSize, in: 100...5000, step: 100)
                }
            }
            Section("Converts to") {
                KeyValueRow(key: "Grams", value: Format.grams(grams))
                KeyValueRow(key: "Kilograms", value: String(format: "%.3f kg", grams / 1000))
                KeyValueRow(key: "Meters", value: Format.length(meters: FilamentMath.gramsToMeters(grams, diameterMM: diameter, densityGcm3: density)))
                KeyValueRow(key: "Feet", value: String(format: "%.1f ft", FilamentMath.gramsToMeters(grams, diameterMM: diameter, densityGcm3: density) * 3.28084))
                KeyValueRow(key: "Volume", value: String(format: "%.1f cm³", FilamentMath.volumeCM3(grams: grams, densityGcm3: density)))
                KeyValueRow(key: "Percent of spool", value: Format.percent(grams / spoolSize * 100))
            }
        }
        .navigationTitle("Converter")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Print cost calculator

struct CostCalculatorView: View {
    @State private var input = CostInput()
    @Query private var projects: [ProjectItem]
    @Environment(\.modelContext) private var context
    @State private var saveToProject: ProjectItem?
    @State private var saved = false

    private var result: CostResult { CostEngine.calculate(input) }

    var body: some View {
        Form {
            Section("Filament") {
                HStack { Text("Grams used"); Spacer(); TextField("0", value: $input.filamentGrams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Spool price"); Spacer(); TextField("0.00", value: $input.filamentPricePerSpool, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Spool size (g)"); Spacer(); TextField("1000", value: $input.spoolSizeGrams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
            }
            Section("Time & Energy") {
                HStack { Text("Print time (h)"); Spacer(); TextField("0", value: $input.printHours, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Printer watts"); Spacer(); TextField("150", value: $input.printerWatts, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Electricity /kWh"); Spacer(); TextField("0.15", value: $input.electricityRatePerKWh, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Machine rate /h"); Spacer(); TextField("0", value: $input.machineHourlyRate, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
            }
            Section("Labor & Extras") {
                HStack { Text("Setup (min)"); Spacer(); TextField("0", value: $input.setupLaborMinutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Finishing (min)"); Spacer(); TextField("0", value: $input.finishingLaborMinutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Labor rate /h"); Spacer(); TextField("0", value: $input.laborRatePerHour, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Consumables"); Spacer(); TextField("0", value: $input.consumablesCost, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Waste %"); Spacer(); TextField("0", value: $input.wastePercent, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Failure allowance %"); Spacer(); TextField("0", value: $input.failureAllowancePercent, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Shipping"); Spacer(); TextField("0", value: $input.shippingCost, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Packaging"); Spacer(); TextField("0", value: $input.packagingCost, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Markup %"); Spacer(); TextField("0", value: $input.markupPercent, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
            }
            Section("Breakdown") {
                KeyValueRow(key: "Filament", value: Format.currency(result.filamentCost))
                KeyValueRow(key: "Electricity", value: Format.currency(result.electricityCost))
                KeyValueRow(key: "Machine", value: Format.currency(result.machineCost))
                KeyValueRow(key: "Labor", value: Format.currency(result.laborCost))
                KeyValueRow(key: "Consumables", value: Format.currency(result.consumablesCost))
                KeyValueRow(key: "Waste", value: Format.currency(result.wasteCost))
                KeyValueRow(key: "Failure allowance", value: Format.currency(result.failureAllowanceCost))
            }
            Section("Result") {
                KeyValueRow(key: "Production cost", value: Format.currency(result.productionCost))
                KeyValueRow(key: "Suggested price", value: Format.currency(result.suggestedPrice))
                KeyValueRow(key: "Profit", value: Format.currency(result.profit))
                KeyValueRow(key: "Gross margin", value: Format.percent(result.grossMarginPercent))
            }
            if !projects.isEmpty {
                Section {
                    Picker("Save to project", selection: $saveToProject) {
                        Text("Don't save").tag(ProjectItem?.none)
                        ForEach(projects) { Text($0.name).tag(ProjectItem?.some($0)) }
                    }
                    if saveToProject != nil {
                        Button(saved ? "Saved ✓" : "Save Calculation to Project") {
                            guard let project = saveToProject else { return }
                            let item = BOMItem()
                            item.project = project
                            item.name = "Print cost calculation"
                            item.category = .filament
                            item.quantity = 1
                            item.unitCost = result.productionCost
                            item.grams = input.filamentGrams
                            context.insert(item)
                            Haptics.success()
                            saved = true
                        }
                        .disabled(saved)
                    }
                }
            }
        }
        .navigationTitle("Print Cost")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !dismissDisabled { EmptyView() }
            }
        }
    }

    private var dismissDisabled: Bool { true }
}

// MARK: - Volumetric flow

struct FlowRateView: View {
    @State private var lineWidth = 0.42
    @State private var layerHeight = 0.2
    @State private var speed = 80.0
    @State private var targetFlow = 12.0
    @Environment(\.modelContext) private var context
    @Query private var printers: [PrinterDevice]
    @Query(sort: \FlowLimitRecord.date, order: .reverse) private var savedLimits: [FlowLimitRecord]
    @State private var limitPrinter: PrinterDevice?
    @State private var limitHotend = ""
    @State private var limitMaterial = "pla"

    var body: some View {
        Form {
            Section("Volumetric Flow") {
                Stepper(value: $lineWidth, in: 0.1...2.0, step: 0.02) { HStack { Text("Line width"); Spacer(); Text(String(format: "%.2f mm", lineWidth)).monospacedDigit() } }
                Stepper(value: $layerHeight, in: 0.05...1.0, step: 0.04) { HStack { Text("Layer height"); Spacer(); Text(String(format: "%.2f mm", layerHeight)).monospacedDigit() } }
                Stepper(value: $speed, in: 5...600, step: 5) { HStack { Text("Speed"); Spacer(); Text("\(Int(speed)) mm/s").monospacedDigit() } }
                KeyValueRow(key: "Volumetric flow", value: String(format: "%.1f mm³/s", FilamentMath.volumetricFlow(lineWidthMM: lineWidth, layerHeightMM: layerHeight, speedMMs: speed)))
            }
            Section("Target Flow → Max Speed") {
                Stepper(value: $targetFlow, in: 0.5...50, step: 0.5) { HStack { Text("Target flow"); Spacer(); Text(String(format: "%.1f mm³/s", targetFlow)).monospacedDigit() } }
                KeyValueRow(key: "Max speed", value: String(format: "%.0f mm/s", FilamentMath.maxSpeed(targetFlowMm3s: targetFlow, lineWidthMM: lineWidth, layerHeightMM: layerHeight)))
            }
            Section("Save Known Limit") {
                Picker("Printer", selection: $limitPrinter) {
                    Text("None").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                TextField("Hotend", text: $limitHotend)
                Picker("Material", selection: $limitMaterial) {
                    ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                }
                Button("Save Limit (\(String(format: "%.1f", targetFlow)) mm³/s)") {
                    let record = FlowLimitRecord()
                    record.printer = limitPrinter
                    record.hotendName = limitHotend
                    record.nozzleDiameter = lineWidth
                    record.materialID = limitMaterial
                    record.maxFlowMm3s = targetFlow
                    context.insert(record)
                    Haptics.success()
                }
            }
            if !savedLimits.isEmpty {
                Section("Known Limits") {
                    ForEach(savedLimits) { limit in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(limit.printer?.displayName ?? "Any printer") · \(MaterialLibrary.shared.material(for: limit.materialID)?.name ?? limit.materialID)")
                                    .font(.subheadline)
                                Text(limit.hotendName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f mm³/s", limit.maxFlowMm3s)).font(.subheadline.monospacedDigit())
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { context.delete(savedLimits[index]) }
                    }
                }
            }
        }
        .navigationTitle("Volumetric Flow")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Print estimator

struct PrintEstimatorView: View {
    @Query private var spools: [Spool]
    @State private var totalMinutes = 300.0
    @State private var totalGrams = 186.0
    @State private var totalLength = 62.0
    @State private var parts = 4.0
    @State private var spool: Spool?

    var body: some View {
        Form {
            Section("Slicer Estimates") {
                HStack { Text("Time (min)"); Spacer(); TextField("0", value: $totalMinutes, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                HStack { Text("Filament (g)"); Spacer(); TextField("0", value: $totalGrams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                HStack { Text("Filament (m)"); Spacer(); TextField("0", value: $totalLength, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                Stepper("Parts \(Int(parts))", value: $parts, in: 1...500)
            }
            Section("Per Part") {
                KeyValueRow(key: "Filament", value: Format.grams(parts > 0 ? totalGrams / parts : 0))
                KeyValueRow(key: "Time", value: Format.duration(minutes: parts > 0 ? totalMinutes / parts : 0))
                if let spool, let perKg = spool.costPerKg {
                    KeyValueRow(key: "Cost", value: Format.currency(totalGrams / parts * perKg / 1000))
                }
            }
            Section("Against Spool") {
                Picker("Spool", selection: $spool) {
                    Text("None").tag(Spool?.none)
                    ForEach(spools.filter { !$0.isArchived }) { Text($0.displayName).tag(Spool?.some($0)) }
                }
                if let spool {
                    let reserve = spool.originalNetWeightG * AppSettings.shared.reservePercent / 100
                    let usable = spool.currentWeightG - reserve
                    let count = FilamentMath.depletionPrints(remainingG: spool.currentWeightG, perPrintG: totalGrams,
                                                             reservePercent: AppSettings.shared.reservePercent, originalG: spool.originalNetWeightG)
                    KeyValueRow(key: "Possible full jobs", value: "\(count)")
                    KeyValueRow(key: "Remaining after one job", value: Format.grams(max(spool.currentWeightG - totalGrams, 0)))
                    if usable < totalGrams {
                        Label("Insufficient filament after the \(Format.percent(AppSettings.shared.reservePercent)) reserve.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Print Estimator")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Multi-spool planner

struct MultiSpoolPlannerView: View {
    @Query private var spools: [Spool]
    @State private var required = 500.0
    @State private var selected: Set<UUID> = []

    private var selectedSpools: [Spool] {
        spools.filter { selected.contains($0.id) }.sorted { $0.currentWeightG > $1.currentWeightG }
    }

    private var totalAvailable: Double {
        selectedSpools.reduce(0) { $0 + $1.currentWeightG }
    }

    private var swapInstructions: [String] {
        var remaining = required
        var instructions: [String] = []
        for (index, spool) in selectedSpools.enumerated() {
            guard remaining > 0 else { break }
            let used = min(remaining, spool.currentWeightG)
            remaining -= used
            if remaining > 0 {
                instructions.append("Swap after \(Format.grams(used)) (spool \(index + 1) empties)")
            }
        }
        return instructions
    }

    var body: some View {
        Form {
            Section("Job Requirement") {
                HStack { Text("Filament needed"); Spacer(); TextField("0", value: $required, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90); Text("g").foregroundStyle(.secondary) }
            }
            Section("Assign Spools") {
                ForEach(spools.filter { !$0.isArchived && $0.currentWeightG > 0 }) { spool in
                    Button {
                        if selected.contains(spool.id) { selected.remove(spool.id) } else { selected.insert(spool.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(spool.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(spool.id) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spool.displayName).font(.subheadline).foregroundStyle(.primary)
                                Text(Format.grams(spool.currentWeightG)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            if !selectedSpools.isEmpty {
                Section("Plan") {
                    KeyValueRow(key: "Total available", value: Format.grams(totalAvailable))
                    if selectedSpools.count == 1 {
                        KeyValueRow(key: "One spool enough?", value: totalAvailable >= required ? "Yes" : "No")
                    }
                    if totalAvailable >= required {
                        ForEach(swapInstructions, id: \.self) { Text($0).font(.subheadline) }
                        KeyValueRow(key: "Reserve left", value: Format.grams(totalAvailable - required))
                    } else {
                        Label("Selected spools are \(Format.grams(required - totalAvailable)) short.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Multi-Spool Planner")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AMS / multicolor planner

struct AMSPlannerView: View {
    @Query private var spools: [Spool]
    @State private var lines: [ColorRequirement] = [ColorRequirement()]

    struct ColorRequirement: Identifiable {
        let id = UUID()
        var label = ""
        var grams: Double = 0
        var spoolID: UUID?
    }

    var body: some View {
        Form {
            Section("Per-Color Estimates from Slicer") {
                ForEach($lines) { $line in
                    HStack {
                        TextField("Color", text: $line.label).frame(width: 80)
                        TextField("g", value: $line.grams, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                        Text("g").foregroundStyle(.secondary)
                        Picker("Spool", selection: $line.spoolID) {
                            Text("Assign…").tag(UUID?.none)
                            ForEach(spools.filter { !$0.isArchived }) { Text($0.displayName).tag(UUID?.some($0.id)) }
                        }
                        .labelsHidden()
                    }
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button("Add Color") { lines.append(ColorRequirement()) }
            }
            Section("Check") {
                ForEach(lines) { line in
                    if let id = line.spoolID, let spool = spools.first(where: { $0.id == id }) {
                        let ok = spool.currentWeightG >= line.grams
                        HStack {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(ok ? Color.green : Color.red)
                            Text("\(line.label.isEmpty ? "Color" : line.label): needs \(Format.grams(line.grams)), spool has \(Format.grams(spool.currentWeightG))")
                                .font(.caption)
                        }
                        .accessibilityLabel("\(line.label): \(ok ? "sufficient" : "insufficient") filament")
                    }
                }
            }
        }
        .navigationTitle("AMS Planner")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shrinkage / scale compensation

struct ShrinkageView: View {
    @Environment(\.modelContext) private var context
    @Query private var printers: [PrinterDevice]
    @State private var designed = SIMD3(40.0, 40.0, 20.0)
    @State private var measured = SIMD3(39.8, 39.8, 20.1)
    @State private var savePrinter: PrinterDevice?
    @State private var saveMaterial = "pla"
    @State private var saved = false

    var body: some View {
        Form {
            Section("Designed (mm)") {
                AxisFields(value: $designed)
            }
            Section("Measured (mm)") {
                AxisFields(value: $measured)
            }
            Section("Compensation") {
                ForEach(["X", "Y", "Z"], id: \.self) { axis in
                    let d = axis == "X" ? designed.x : axis == "Y" ? designed.y : designed.z
                    let m = axis == "X" ? measured.x : axis == "Y" ? measured.y : measured.z
                    let result = FilamentMath.scaleCompensation(designed: d, measured: m)
                    HStack {
                        Text(axis).font(.headline).frame(width: 20)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%+.2f mm (%+.2f%%)", result.error, result.percentError))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("Scale × \(String(format: "%.4f", result.scaleFactor))")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
            Section("Save Profile") {
                Picker("Printer", selection: $savePrinter) {
                    Text("None").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                Picker("Material", selection: $saveMaterial) {
                    ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                }
                Button(saved ? "Saved ✓" : "Save Calibration Record") {
                    let record = CalibrationRecord()
                    record.typeKey = "dimensional"
                    record.printer = savePrinter
                    record.materialID = saveMaterial
                    let x = FilamentMath.scaleCompensation(designed: designed.x, measured: measured.x)
                    let y = FilamentMath.scaleCompensation(designed: designed.y, measured: measured.y)
                    let z = FilamentMath.scaleCompensation(designed: designed.z, measured: measured.z)
                    record.resultSummary = String(format: "X ×%.4f · Y ×%.4f · Z ×%.4f", x.scaleFactor, y.scaleFactor, z.scaleFactor)
                    record.numericResult = x.scaleFactor
                    context.insert(record)
                    Haptics.success()
                    saved = true
                }
                .disabled(saved)
            }
        }
        .navigationTitle("Shrinkage Compensation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct AxisFields: View {
        @Binding var value: SIMD3<Double>
        var body: some View {
            HStack { Text("X"); Spacer(); TextField("0", value: $value.x, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
            HStack { Text("Y"); Spacer(); TextField("0", value: $value.y, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
            HStack { Text("Z"); Spacer(); TextField("0", value: $value.z, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
        }
    }
}

// MARK: - Hole compensation

struct HoleCompensationView: View {
    @Environment(\.modelContext) private var context
    @Query private var printers: [PrinterDevice]
    @State private var designed = 6.0
    @State private var measured = 5.7
    @State private var printer: PrinterDevice?
    @State private var materialID = "pla"
    @State private var nozzleDiameter = 0.4
    @State private var layerHeight = 0.2
    @State private var saved = false

    var body: some View {
        Form {
            Section("Measurement") {
                HStack { Text("Designed diameter"); Spacer(); TextField("0", value: $designed, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90); Text("mm").foregroundStyle(.secondary) }
                HStack { Text("Measured diameter"); Spacer(); TextField("0", value: $measured, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90); Text("mm").foregroundStyle(.secondary) }
            }
            Section("Correction") {
                let correction = FilamentMath.holeCompensation(designedMM: designed, measuredMM: measured)
                KeyValueRow(key: "Hole prints smaller by", value: String(format: "%.2f mm", correction))
                KeyValueRow(key: "Model holes at", value: String(format: "%.2f mm", designed + correction))
            }
            Section("Context (saved with the entry)") {
                Picker("Printer", selection: $printer) {
                    Text("None").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                Picker("Material", selection: $materialID) {
                    ForEach(MaterialLibrary.shared.materials) { Text($0.name).tag($0.id) }
                }
                Stepper("Nozzle \(String(format: "%.2g", nozzleDiameter)) mm", value: $nozzleDiameter, in: 0.2...1.2, step: 0.2)
                Stepper("Layer \(String(format: "%.2f", layerHeight)) mm", value: $layerHeight, in: 0.08...0.6, step: 0.04)
                Button(saved ? "Saved ✓" : "Save to Tolerance Library") {
                    let entry = ToleranceEntry()
                    entry.category = .thread
                    entry.clearanceMm = FilamentMath.holeCompensation(designedMM: designed, measuredMM: measured)
                    entry.printer = printer
                    entry.materialID = materialID
                    entry.nozzleDiameter = nozzleDiameter
                    entry.layerHeight = layerHeight
                    entry.notes = "Hole compensation: designed \(designed) mm, measured \(measured) mm"
                    context.insert(entry)
                    Haptics.success()
                    saved = true
                }
                .disabled(saved)
            }
        }
        .navigationTitle("Hole Compensation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
