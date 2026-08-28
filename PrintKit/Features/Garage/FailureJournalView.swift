import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Failure journal list

struct FailureJournalView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FailureReport.date, order: .reverse) private var reports: [FailureReport]
    @State private var showAdd = false
    @State private var search = ""

    private var filtered: [FailureReport] {
        guard !search.isEmpty else { return reports }
        let q = search.lowercased()
        return reports.filter {
            $0.category.lowercased().contains(q)
            || $0.suspectedCause.lowercased().contains(q)
            || $0.finalSolution.lowercased().contains(q)
            || ($0.printer?.displayName.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        List {
            if reports.isEmpty {
                PKEmptyState(symbol: "exclamationmark.bubble",
                             title: "No Failures Logged",
                             message: "When a print fails, record the cause and the fix. Future-you will thank present-you — solved fixes resurface in Troubleshooting.",
                             actionTitle: "Log a Failure") { showAdd = true }
            }
            ForEach(filtered) { report in
                NavigationLink { FailureReportDetailView(report: report) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(report.category.isEmpty ? "Failure" : report.category)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            StatusBadge(status: report.finalSolution.isEmpty ? .attention : .ready,
                                        text: report.finalSolution.isEmpty ? "Open" : "Solved")
                        }
                        if !report.suspectedCause.isEmpty {
                            Text(report.suspectedCause)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text([
                            report.printer?.displayName,
                            Format.date(report.date)
                        ].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(filtered[i]) }
            }
        }
        .searchable(text: $search, prompt: "Search causes & fixes")
        .navigationTitle("Failure Journal")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { NavigationStack { FailureReportFormView(report: nil) } }
    }
}

// MARK: - Detail

struct FailureReportDetailView: View {
    @Bindable var report: FailureReport
    @State private var showEdit = false

    var body: some View {
        List {
            Section {
                HStack(spacing: PK.Spacing.sm) {
                    StatusBadge(status: report.finalSolution.isEmpty ? .attention : .ready,
                                text: report.finalSolution.isEmpty ? "Open" : "Solved")
                    Spacer()
                    Text(Format.dateTime(report.date)).font(.caption).foregroundStyle(.secondary)
                }
                if let printer = report.printer { KeyValueRow(key: "Printer", value: printer.displayName) }
                if let spool = report.spool { KeyValueRow(key: "Spool", value: spool.displayName) }
                if let profile = report.profile { KeyValueRow(key: "Profile", value: profile.name) }
                if !report.settingsSummary.isEmpty {
                    KeyValueRow(key: "Settings", value: report.settingsSummary)
                }
            }

            if !report.suspectedCause.isEmpty {
                Section("Suspected Cause") { Text(report.suspectedCause) }
            }
            if !report.attemptedFix.isEmpty {
                Section("Attempted Fix") { Text(report.attemptedFix) }
            }
            if !report.finalSolution.isEmpty {
                Section("Final Solution") { Text(report.finalSolution) }
            }
            if !report.notes.isEmpty {
                Section("Notes") { Text(report.notes) }
            }

            if report.beforePhoto != nil || report.afterPhoto != nil {
                Section("Before / After") {
                    HStack(spacing: PK.Spacing.md) {
                        if let data = report.beforePhoto, let image = UIImage(data: data) {
                            VStack {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: PK.Radius.card))
                                Text("Before").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let data = report.afterPhoto, let image = UIImage(data: data) {
                            VStack {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: PK.Radius.card))
                                Text("After").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(report.category.isEmpty ? "Failure" : report.category)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { showEdit = true } } }
        .sheet(isPresented: $showEdit) { NavigationStack { FailureReportFormView(report: report) } }
    }
}

// MARK: - Form

struct FailureReportFormView: View {
    let report: FailureReport?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var printers: [PrinterDevice]
    @Query private var spools: [Spool]
    @Query private var profiles: [SlicerProfile]

    @State private var category = ""
    @State private var suspectedCause = ""
    @State private var attemptedFix = ""
    @State private var finalSolution = ""
    @State private var settingsSummary = ""
    @State private var notes = ""
    @State private var printer: PrinterDevice?
    @State private var spool: Spool?
    @State private var profile: SlicerProfile?
    @State private var beforePhoto: Data?
    @State private var afterPhoto: Data?
    @State private var beforePicker: PhotosPickerItem?
    @State private var afterPicker: PhotosPickerItem?

    var body: some View {
        Form {
            Section("What Happened") {
                TextField("Category (e.g. Warping, Clog, Layer Shift)", text: $category)
                Picker("Printer", selection: $printer) {
                    Text("None").tag(PrinterDevice?.none)
                    ForEach(printers) { Text($0.displayName).tag(PrinterDevice?.some($0)) }
                }
                Picker("Spool", selection: $spool) {
                    Text("None").tag(Spool?.none)
                    ForEach(spools) { Text($0.displayName).tag(Spool?.some($0)) }
                }
                Picker("Profile", selection: $profile) {
                    Text("None").tag(SlicerProfile?.none)
                    ForEach(profiles) { Text($0.name).tag(SlicerProfile?.some($0)) }
                }
                TextField("Settings snapshot (e.g. 242 °C · 80 mm/s)", text: $settingsSummary)
            }
            Section("Diagnosis") {
                TextField("Suspected cause", text: $suspectedCause, axis: .vertical).lineLimit(2...5)
                TextField("Attempted fix", text: $attemptedFix, axis: .vertical).lineLimit(2...5)
                TextField("Final solution", text: $finalSolution, axis: .vertical).lineLimit(2...5)
            }
            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 70)
            }
            Section("Photos") {
                PhotosPicker(selection: $beforePicker, matching: .images) {
                    Label(beforePhoto == nil ? "Add Before Photo" : "Change Before Photo", systemImage: "photo")
                }
                PhotosPicker(selection: $afterPicker, matching: .images) {
                    Label(afterPhoto == nil ? "Add After Photo" : "Change After Photo", systemImage: "photo")
                }
            }
        }
        .navigationTitle(report == nil ? "Log Failure" : "Edit Failure")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear {
            guard let report else { return }
            category = report.category
            suspectedCause = report.suspectedCause
            attemptedFix = report.attemptedFix
            finalSolution = report.finalSolution
            settingsSummary = report.settingsSummary
            notes = report.notes
            printer = report.printer
            spool = report.spool
            profile = report.profile
            beforePhoto = report.beforePhoto
            afterPhoto = report.afterPhoto
        }
        .onChange(of: beforePicker) { _, item in load(item, into: $beforePhoto) }
        .onChange(of: afterPicker) { _, item in load(item, into: $afterPhoto) }
    }

    private func load(_ item: PhotosPickerItem?, into binding: Binding<Data?>) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                binding.wrappedValue = data
            }
        }
    }

    private func save() {
        let target: FailureReport
        if let report { target = report } else {
            target = FailureReport()
            context.insert(target)
        }
        target.category = category
        target.suspectedCause = suspectedCause
        target.attemptedFix = attemptedFix
        target.finalSolution = finalSolution
        target.settingsSummary = settingsSummary
        target.notes = notes
        target.printer = printer
        target.spool = spool
        target.profile = profile
        target.beforePhoto = beforePhoto
        target.afterPhoto = afterPhoto
        dismiss()
    }
}
