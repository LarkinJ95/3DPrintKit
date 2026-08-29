import SwiftUI
import SwiftData
import AuthenticationServices
import UniformTypeIdentifiers

private struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query private var printers: [PrinterDevice]

    @State private var syncEngine = SyncEngine.shared
    @State private var auth = AuthManager.shared

    @State private var exportJSONDocument: ExportDocument?
    @State private var exportCSVDocument: ExportDocument?
    @State private var showJSONExporter = false
    @State private var showCSVExporter = false
    @State private var showImportPicker = false
    @State private var importMessage: String?
    @State private var showEraseConfirm = false
    @State private var showSampleConfirm = false
    @State private var apiURL: String = UserDefaults.standard.string(forKey: "apiBaseURL") ?? PrintKitAPIConfiguration.defaultBaseURL
    @Environment(EntitlementService.self) private var entitlements

    var body: some View {
        @Bindable var settings = settings
        Form {
            // MARK: 3dPrintKit Pro
            Section {
                NavigationLink { ProSettingsView() } label: {
                    HStack {
                        Label("3dPrintKit Pro", systemImage: "sparkles")
                        Spacer()
                        Text(entitlements.planTitle.replacingOccurrences(of: "3dPrintKit Pro — ", with: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(entitlements.isPro
                     ? "Thank you for supporting 3dPrintKit."
                     : "Free includes the material database, every calculator, and a small inventory — with no ads.")
            }

            // MARK: Account & Sync
            Section {
                switch auth.state {
                case .signedIn(let name):
                    HStack {
                        Label(name.isEmpty ? "Signed In" : name, systemImage: "person.crop.circle.fill")
                        Spacer()
                        Button("Sign Out", role: .destructive) { auth.signOut() }
                            .font(.subheadline)
                    }
                case .signingIn:
                    HStack { ProgressView(); Text("Signing in…").foregroundStyle(.secondary) }
                case .signedOut, .failed:
                    NavigationLink {
                        SignInView()
                    } label: {
                        Label("Sign in to sync", systemImage: "person.crop.circle.badge.plus")
                    }
                }

                HStack {
                    TextField("API base URL (https://…)", text: $apiURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().font(.subheadline)
                    if apiURL != (UserDefaults.standard.string(forKey: "apiBaseURL") ?? "") {
                        Button("Save") {
                            PrintKitAPIConfiguration.setBaseURL(apiURL.trimmingCharacters(in: .whitespaces))
                            syncEngine.refreshAvailability()
                        }
                    }
                }

                if auth.isSignedIn {
                    HStack {
                        Label(syncLabel, systemImage: syncIcon)
                        Spacer()
                        Button("Sync Now") {
                            Task { await syncEngine.syncNow(context: context) }
                        }
                        .disabled(syncEngine.status == .syncing)
                    }
                    if syncEngine.pendingCount > 0 {
                        Text("\(syncEngine.pendingCount) change\(syncEngine.pendingCount == 1 ? "" : "s") waiting to upload")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let last = syncEngine.lastSyncAt {
                        KeyValueRow(key: "Last synced", value: Format.dateTime(last))
                    }
                } else {
                    Text("3DPrintKit works fully offline. Sign in only if you run your own 3DPrintKit server for multi-device sync.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Sync & Account") }

            // MARK: Preferences
            Section("Preferences") {
                Toggle("Metric units", isOn: $settings.metricUnits)
                Toggle("Temperatures in °C", isOn: $settings.temperatureCelsius)
                HStack {
                    Text("Currency")
                    Spacer()
                    TextField("USD", text: $settings.currencyCode)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .frame(width: 80)
                }
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
            }

            // MARK: Defaults
            Section("Print Defaults") {
                Picker("Default printer", selection: $settings.defaultPrinterID) {
                    Text("None").tag(UUID?.none)
                    ForEach(printers) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                Picker("Default material", selection: $settings.defaultMaterialID) {
                    ForEach(MaterialLibrary.shared.materials) { material in
                        Text(material.name).tag(material.id)
                    }
                }
                Picker("Filament diameter", selection: $settings.defaultDiameter) {
                    Text("1.75 mm").tag(1.75)
                    Text("2.85 mm").tag(2.85)
                }
                PKNumericField(label: "Default spool size", value: $settings.defaultSpoolGrams, unit: "g", placeholder: "1000", keyboard: .numberPad)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Reserve")
                        Spacer()
                        Text(Format.percent(settings.reservePercent))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.reservePercent, in: 0...30, step: 5)
                    Text("Print estimators keep this much of every spool in reserve.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                PKNumericField(label: "Low-spool threshold", value: $settings.lowSpoolThresholdGrams, unit: "g", placeholder: "150", keyboard: .numberPad)
            }

            // MARK: Notifications
            Section("Notifications") {
                Toggle("Drying completion", isOn: $settings.dryingNotificationsEnabled)
                Toggle("Maintenance reminders", isOn: $settings.maintenanceNotificationsEnabled)
            }

            // MARK: Data
            Section {
                Button {
                    do {
                        exportJSONDocument = ExportDocument(data: try DataPorting.exportJSON(context: context))
                        showJSONExporter = true
                    } catch {
                        importMessage = "Could not create the JSON backup: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Export Full Backup (JSON)", systemImage: "square.and.arrow.up")
                }
                Button {
                    do {
                        exportCSVDocument = ExportDocument(data: try DataPorting.exportSpoolsCSV(context: context))
                        showCSVExporter = true
                    } catch {
                        importMessage = "Could not create the CSV export: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Export Spool Inventory (CSV)", systemImage: "tablecells")
                }
                Button {
                    showImportPicker = true
                } label: {
                    Label("Import Backup (JSON)", systemImage: "square.and.arrow.down")
                }
                if let importMessage {
                    Text(importMessage).font(.caption).foregroundStyle(.secondary)
                }

                if !settings.sampleDataLoaded {
                    Button { showSampleConfirm = true } label: {
                        Label("Load Sample Data", systemImage: "sparkles")
                    }
                }

                Button(role: .destructive) { showEraseConfirm = true } label: {
                    Label("Erase All Local Data", systemImage: "trash")
                }
            } header: {
                Text("Backup & Data")
            } footer: {
                Text("Backups are versioned (“printkit.export” v1). Importing never overwrites existing records — duplicates are skipped by ID.")
            }

            // MARK: About
            Section("About") {
                KeyValueRow(key: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                KeyValueRow(key: "Material database", value: "\(MaterialLibrary.shared.materials.count) materials")
                KeyValueRow(key: "Data storage", value: "On-device (SwiftData)")
            }
        }
        .navigationTitle("Settings")
        .pkDismissableKeyboard()
        .fileExporter(isPresented: $showJSONExporter,
                      document: exportJSONDocument,
                      contentType: .json,
                      defaultFilename: "3DPrintKit-Backup") { result in
            if case .failure(let error) = result {
                importMessage = "Could not save the JSON backup: \(error.localizedDescription)"
            }
        }
        .fileExporter(isPresented: $showCSVExporter,
                      document: exportCSVDocument,
                      contentType: .commaSeparatedText,
                      defaultFilename: "3DPrintKit-Spool-Inventory") { result in
            if case .failure(let error) = result {
                importMessage = "Could not save the CSV export: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Load Sample Data?", isPresented: $showSampleConfirm) {
            Button("Load") {
                DataSeeder.loadSampleData(context: context)
                settings.sampleDataLoaded = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds an example printer, spools, a known-good profile, and a print record so you can explore every feature.")
        }
        .alert("Erase All Local Data?", isPresented: $showEraseConfirm) {
            Button("Erase Everything", role: .destructive) { eraseAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every spool, printer, profile, print record, and project on this device. Export a backup first. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    private var syncLabel: String {
        switch syncEngine.status {
        case .disabled: return "Sync unavailable"
        case .idle: return "Up to date"
        case .syncing: return "Syncing…"
        case .offline: return "Offline — will retry"
        case .failed: return "Sync failed"
        }
    }

    private var syncIcon: String {
        switch syncEngine.status {
        case .disabled: return "icloud.slash"
        case .idle: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .failed: return "exclamationmark.icloud"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let report = try DataPorting.importJSON(data, context: context)
                importMessage = "Imported \(report.spoolsAdded) spool\(report.spoolsAdded == 1 ? "" : "s"); skipped \(report.spoolsSkipped) duplicate\(report.spoolsSkipped == 1 ? "" : "s")."
            } catch {
                importMessage = error.localizedDescription
            }
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }

    private func eraseAll() {
        try? context.delete(model: Spool.self)
        try? context.delete(model: DryingSession.self)
        try? context.delete(model: StorageLocation.self)
        try? context.delete(model: FilamentTransfer.self)
        try? context.delete(model: DesiccantUnit.self)
        try? context.delete(model: EnvironmentLog.self)
        try? context.delete(model: WishlistItem.self)
        try? context.delete(model: PurchaseRecord.self)
        try? context.delete(model: PrinterDevice.self)
        try? context.delete(model: NozzleRecord.self)
        try? context.delete(model: BuildPlate.self)
        try? context.delete(model: AccessoryItem.self)
        try? context.delete(model: MaintenanceTask.self)
        try? context.delete(model: MaintenanceLog.self)
        try? context.delete(model: PrintRecord.self)
        try? context.delete(model: ProjectItem.self)
        try? context.delete(model: BOMItem.self)
        try? context.delete(model: PrintQueueItem.self)
        try? context.delete(model: FailureReport.self)
        try? context.delete(model: SlicerProfile.self)
        try? context.delete(model: CalibrationRecord.self)
        try? context.delete(model: ToleranceEntry.self)
        try? context.delete(model: FlowLimitRecord.self)
        try? context.delete(model: MaterialOverride.self)
        settings.sampleDataLoaded = false
    }
}

/// A dedicated account screen. Local PrintKit data remains usable when the
/// person elects not to connect a Cloudflare sync server.
private struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthManager.shared
    @State private var apiURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? PrintKitAPIConfiguration.defaultBaseURL

    private var normalizedURL: String {
        apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PK.Spacing.lg) {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .padding(.top, PK.Spacing.xl)

                VStack(spacing: PK.Spacing.sm) {
                    Text("Sync your 3DPrintKit")
                        .font(.title2.bold())
                    Text("Keep your printers, spools, and projects in sync across your devices.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: PK.Spacing.xs) {
                    Text("3DPrintKit server")
                        .font(.subheadline.weight(.medium))
                    TextField("https://api.example.com", text: $apiURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .padding(PK.Spacing.sm)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    Text("Enter the URL of your deployed 3DPrintKit Cloudflare Worker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case .signingIn = auth.state {
                    ProgressView("Signing in…")
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        auth.handleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    .disabled(normalizedURL.isEmpty)
                }

                if normalizedURL.isEmpty {
                    Text("Add your server URL to enable Sign in with Apple.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case .failed(let message) = auth.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Continue Offline") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, PK.Spacing.lg)
            .padding(.bottom, PK.Spacing.xl)
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: apiURL) { _, newValue in
            PrintKitAPIConfiguration.setBaseURL(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .onChange(of: auth.state) { _, state in
            if case .signedIn = state { dismiss() }
        }
    }
}
