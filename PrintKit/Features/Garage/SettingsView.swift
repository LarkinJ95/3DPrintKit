import SwiftUI
import SwiftData
import AuthenticationServices

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query private var printers: [PrinterDevice]

    @State private var syncEngine = SyncEngine.shared
    @State private var auth = AuthManager.shared

    @State private var exportJSONData: Data?
    @State private var exportCSVData: Data?
    @State private var showImportPicker = false
    @State private var importMessage: String?
    @State private var showEraseConfirm = false
    @State private var showSampleConfirm = false
    @State private var apiURL: String = UserDefaults.standard.string(forKey: "apiBaseURL") ?? PrintKitAPIConfiguration.defaultBaseURL

    var body: some View {
        @Bindable var settings = settings
        Form {
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
                HStack {
                    Text("Default spool size")
                    Spacer()
                    TextField("1000", value: $settings.defaultSpoolGrams, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("g").foregroundStyle(.secondary)
                }
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
                HStack {
                    Text("Low-spool threshold")
                    Spacer()
                    TextField("150", value: $settings.lowSpoolThresholdGrams, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                    Text("g").foregroundStyle(.secondary)
                }
            }

            // MARK: Notifications
            Section("Notifications") {
                Toggle("Drying completion", isOn: $settings.dryingNotificationsEnabled)
                Toggle("Maintenance reminders", isOn: $settings.maintenanceNotificationsEnabled)
            }

            // MARK: Data
            Section {
                Button {
                    exportJSONData = try? DataPorting.exportJSON(context: context)
                } label: {
                    Label("Export Full Backup (JSON)", systemImage: "square.and.arrow.up")
                }
                Button {
                    exportCSVData = try? DataPorting.exportSpoolsCSV(context: context)
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
        // Exporters
        .sheet(item: exportJSONBinding) { item in
            ShareLink(item: item.data, preview: SharePreview("3DPrintKit Backup", image: Image(systemName: "square.and.arrow.up"))) {
                Label("Share Backup", systemImage: "square.and.arrow.up")
            }
            .presentationDetents([.medium])
        }
        .sheet(item: exportCSVBinding) { item in
            ShareLink(item: item.data, preview: SharePreview("Spool Inventory CSV", image: Image(systemName: "tablecells"))) {
                Label("Share CSV", systemImage: "square.and.arrow.up")
            }
            .presentationDetents([.medium])
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

    private struct ShareItem: Identifiable {
        let id = UUID()
        let data: Data
    }

    private var exportJSONBinding: Binding<ShareItem?> {
        Binding(
            get: { exportJSONData.map { ShareItem(data: $0) } },
            set: { if $0 == nil { exportJSONData = nil } }
        )
    }

    private var exportCSVBinding: Binding<ShareItem?> {
        Binding(
            get: { exportCSVData.map { ShareItem(data: $0) } },
            set: { if $0 == nil { exportCSVData = nil } }
        )
    }

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
