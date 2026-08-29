import Foundation
import SwiftData

/// Local-first synchronization with the PrintKit backend.
///
/// Strategy (per spec):
/// * SwiftData is the immediate working database — UI never waits on network.
/// * Mutations are journaled as pending operations (create/update/delete).
/// * The engine pushes the journal and pulls incremental changes using a
///   server cursor (`GET /api/v1/sync?since=`), applying tombstones.
/// * Historical records (prints, drying, maintenance, failures, purchases)
///   are treated as append-only.
/// * Spool weight changes are submitted as *deltas* (deduct/add), never as
///   absolute values, so two devices can't blindly overwrite each other.
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case disabled          // no server configured or signed out
        case idle
        case syncing
        case offline
        case failed(String)
    }

    private(set) var status: Status = .disabled
    private(set) var lastSyncAt: Date?
    private(set) var pendingCount: Int = 0

    private let journalKey = "printkit.sync.journal"
    private let cursorKey = "printkit.sync.cursor"

    private init() {
        pendingCount = journal().count
        refreshAvailability()
    }

    func refreshAvailability() {
        if !APIClient.shared.isConfigured || !AuthManager.shared.isSignedIn {
            status = .disabled
        } else if case .syncing = status {
            // keep
        } else {
            status = .idle
        }
    }

    // MARK: - Journal

    struct PendingOperation: Codable {
        enum Kind: String, Codable { case create, update, delete, filamentDelta }
        let id: UUID
        let kind: Kind
        let entity: String          // "spools", "printers", ...
        let recordID: UUID
        let payload: Data?          // JSON-encoded record (create/update)
        let deltaGrams: Double?     // for filamentDelta
        let queuedAt: Date
    }

    /// Canonical server payload for a spool. NFC/QR tags intentionally carry
    /// only a compact identification subset, so they must never be reused as
    /// a sync mutation payload.
    private struct SpoolPushPayload: Encodable {
        let id, manufacturer, product_line, material_id, color_name, color_hex, finish: String
        let diameter, original_net_weight_g, current_weight_g, empty_spool_weight_g, cost: Double
        let vendor: String
        let purchase_date, opened_date, last_used_date, last_dried_date: String?
        let lot_number, batch_number: String
        let lot_flagged: Bool
        let lot_notes, notes: String
        let nfc_tag_written, is_favorite, is_archived: Bool
        let storage_location_id: String?
        let ams_slot_label: String
    }

    private func journal() -> [PendingOperation] {
        guard let data = UserDefaults.standard.data(forKey: journalKey),
              let ops = try? JSONDecoder().decode([PendingOperation].self, from: data) else { return [] }
        return ops
    }

    private func saveJournal(_ ops: [PendingOperation]) {
        if let data = try? JSONEncoder().encode(ops) {
            UserDefaults.standard.set(data, forKey: journalKey)
        }
        pendingCount = ops.count
    }

    func enqueue(_ op: PendingOperation) {
        var ops = journal()
        ops.append(op)
        saveJournal(ops)
    }

    func enqueueSpool(_ spool: Spool, kind: PendingOperation.Kind) {
        let formatter = ISO8601DateFormatter()
        let payload = SpoolPushPayload(
            id: spool.id.uuidString, manufacturer: spool.manufacturer, product_line: spool.productLine,
            material_id: spool.materialID, color_name: spool.colorName, color_hex: spool.colorHex,
            finish: spool.finishRaw, diameter: spool.diameter, original_net_weight_g: spool.originalNetWeightG,
            current_weight_g: spool.currentWeightG, empty_spool_weight_g: spool.emptySpoolWeightG,
            cost: spool.cost, vendor: spool.vendor, purchase_date: spool.purchaseDate.map(formatter.string),
            opened_date: spool.openedDate.map(formatter.string), last_used_date: spool.lastUsedDate.map(formatter.string),
            last_dried_date: spool.lastDriedDate.map(formatter.string), lot_number: spool.lotNumber,
            batch_number: spool.batchNumber, lot_flagged: spool.lotFlagged, lot_notes: spool.lotNotes,
            notes: spool.notes, nfc_tag_written: spool.nfcTagWritten, is_favorite: spool.isFavorite,
            is_archived: spool.isArchived, storage_location_id: spool.storageLocation?.id.uuidString,
            ams_slot_label: spool.amsSlotLabel
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        enqueue(.init(id: UUID(), kind: kind, entity: "spools", recordID: spool.id,
                      payload: try? encoder.encode(payload), deltaGrams: nil, queuedAt: Date()))
    }

    // MARK: - Sync cycle

    struct SyncPushRequest: Encodable {
        let operations: [OperationPayload]
        struct OperationPayload: Encodable {
            let id: String
            let kind: String
            let entity: String
            let record_id: String
            let payload: String?      // JSON string
            let delta_grams: Double?
        }
    }

    struct SyncPushResponse: Decodable {
        let accepted: [String]
        let rejected: [RejectedOperation]?
        struct RejectedOperation: Decodable {
            let id: String
            let reason: String
        }
    }

    struct SyncPullResponse: Decodable {
        let cursor: String
        let changes: [Change]?
        let spools: [SpoolSyncDTO]?
        let deleted: [Tombstone]?
        let has_more: Bool?

        struct Change: Decodable {
            let cursor: String
            let entity: String
            let record_id: String
            let op: String
            let payload: String?
        }
        struct Tombstone: Decodable {
            let entity: String
            let record_id: String
        }
    }

    struct SpoolSyncDTO: Codable {
        let id: String
        let manufacturer: String
        let product_line: String
        let material_id: String
        let color_name: String
        let color_hex: String?
        let diameter: Double
        let original_weight_g: Double
        let current_weight_g: Double
        let empty_spool_weight_g: Double
        let notes: String
        let archived: Bool
        let updated_at: Date
    }

    private struct SpoolWire: Decodable {
        let id, manufacturer, product_line, material_id, color_name, color_hex, finish: String
        let diameter, original_net_weight_g, current_weight_g, empty_spool_weight_g, cost: Double
        let vendor: String
        let lot_number, batch_number, lot_notes, notes, ams_slot_label: String
        let lot_flagged, nfc_tag_written, is_favorite, is_archived: Bool
    }
    private struct PrinterWire: Decodable {
        let id, manufacturer, model, custom_name, extruder_type, ams_type, notes: String
        let max_hotend_temp_c, max_bed_temp_c, total_print_hours: Double
        let has_enclosure, has_heated_chamber: Bool
        let ams_slot_count: Int
    }
    private struct ProfileWire: Decodable {
        let id, name, material_id, filament_product, notes: String
        let printer_id: String?
        let nozzle_diameter, layer_height, nozzle_temp, bed_temp, print_speed, flow_ratio: Double
        let is_known_good: Bool
        let success_count, failure_count: Int
    }
    private struct PrintWire: Decodable {
        let id, name, material_id, profile_id, project_id, printer_id, spool_id, date, category, notes: String?
        let duration_minutes, grams_used, cost: Double
        let success: Bool
    }
    private struct ProjectWire: Decodable {
        let id, name, notes, status, created_at: String
        let completed_at: String?
    }
    private struct MaintenanceWire: Decodable {
        let id, printer_id, name: String
        let interval_days: Int
        let interval_print_hours: Double
        let last_completed: String?
    }

    @MainActor
    func syncNow(context: ModelContext) async {
        // Access tokens are deliberately short-lived. Refresh before every
        // cycle so downloads keep working after the initial sign-in window.
        await AuthManager.shared.refreshSessionIfNeeded()
        refreshAvailability()
        guard status != .disabled else { return }
        status = .syncing
        defer { refreshAvailability() }

        do {
            try await pushJournal()
            try await pullChanges(context: context)
            // Pulling a legacy spool can queue its missing colour swatch for
            // repair. Send that small follow-up batch in the same user-initiated
            // cycle instead of requiring a second tap of Sync Now.
            try await pushJournal()
            lastSyncAt = Date()
            Haptics.light()
        } catch let error as APIError {
            if case .transport = error { status = .offline } else { status = .failed(error.localizedDescription) }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func pushJournal() async throws {
        var ops = journal()
        guard !ops.isEmpty else { return }

        let payload = SyncPushRequest(operations: ops.map {
            .init(id: $0.id.uuidString,
                  kind: $0.kind.rawValue,
                  entity: $0.entity,
                  record_id: $0.recordID.uuidString,
                  payload: $0.payload.flatMap { String(data: $0, encoding: .utf8) },
                  delta_grams: $0.deltaGrams)
        })
        let response: SyncPushResponse = try await APIClient.shared.request("POST", "/api/v1/sync", body: payload)
        let rejectedIDs = Set(response.rejected?.map(\.id) ?? [])
        ops.removeAll { op in
            response.accepted.contains(op.id.uuidString) || rejectedIDs.contains(op.id.uuidString)
        }
        saveJournal(ops)
    }

    private func pullChanges(context: ModelContext) async throws {
        var cursor = UserDefaults.standard.string(forKey: cursorKey) ?? ""
        while true {
            let response: SyncPullResponse = try await APIClient.shared.request(
                "GET", "/api/v1/sync", query: ["since": cursor]
            )

            // New servers return a single ordered stream for every entity. The
            // spool-only fields are retained as a compatibility fallback while a
            // device rolls forward to this implementation.
            if let changes = response.changes {
                for change in changes {
                    guard let id = UUID(uuidString: change.record_id) else { continue }
                    if change.op == "delete" {
                        try deleteLocal(entity: change.entity, id: id, context: context)
                        continue
                    }
                    guard let payload = change.payload else { continue }
                    try applySnapshot(entity: change.entity, payload: payload, context: context)
                }
            } else {
                for tombstone in response.deleted ?? [] where tombstone.entity == "spools" {
                    if let uuid = UUID(uuidString: tombstone.record_id), let spool = try fetchSpool(uuid, context: context) {
                        context.delete(spool)
                    }
                }
                for dto in response.spools ?? [] { try applySpool(dto, context: context) }
            }

            UserDefaults.standard.set(response.cursor, forKey: cursorKey)
            try context.save()
            guard response.has_more == true, response.cursor != cursor else { return }
            cursor = response.cursor
        }
    }

    private func applySpool(_ dto: SpoolSyncDTO, context: ModelContext) throws {
            guard let uuid = UUID(uuidString: dto.id) else { return }
            if let existing = try fetchSpool(uuid, context: context) {
                // Server weight is authoritative only when newer; local pending
                // deltas were already pushed above.
                existing.manufacturer = dto.manufacturer
                existing.productLine = dto.product_line
                existing.materialID = dto.material_id
                existing.colorName = dto.color_name
                if let colorHex = dto.color_hex, !colorHex.isEmpty {
                    existing.colorHex = colorHex
                } else if shouldBackfillColor(existing.colorHex) {
                    // Records written by the original tag-oriented sync format
                    // only contain a colour name. If this device has the
                    // selected swatch, republish it once in the canonical
                    // payload so other devices no longer receive gray.
                    enqueueSpool(existing, kind: .update)
                }
                existing.diameter = dto.diameter
                existing.originalNetWeightG = dto.original_weight_g
                existing.currentWeightG = dto.current_weight_g
                existing.emptySpoolWeightG = dto.empty_spool_weight_g
                existing.notes = dto.notes
                existing.isArchived = dto.archived
            } else {
                let spool = Spool()
                spool.id = uuid
                spool.manufacturer = dto.manufacturer
                spool.productLine = dto.product_line
                spool.materialID = dto.material_id
                spool.colorName = dto.color_name
                if let colorHex = dto.color_hex, !colorHex.isEmpty {
                    spool.colorHex = colorHex
                }
                spool.diameter = dto.diameter
                spool.originalNetWeightG = dto.original_weight_g
                spool.currentWeightG = dto.current_weight_g
                spool.emptySpoolWeightG = dto.empty_spool_weight_g
                spool.notes = dto.notes
                spool.isArchived = dto.archived
                context.insert(spool)
            }
    }

    /// Avoid turning an unknown legacy colour into the model's placeholder
    /// gray. Any deliberate non-default swatch can safely repair the server
    /// record on the next push.
    private func shouldBackfillColor(_ hex: String) -> Bool {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
            && trimmed.caseInsensitiveCompare("#808080") != .orderedSame
    }

    private func applySnapshot(entity: String, payload: String, context: ModelContext) throws {
        let data = Data(payload.utf8)
        let decoder = JSONDecoder()
        switch entity {
        case "spools":
            let wire = try decoder.decode(SpoolWire.self, from: data)
            guard let id = UUID(uuidString: wire.id) else { return }
            let spool = try fetchSpool(id, context: context) ?? Spool()
            spool.id = id; spool.manufacturer = wire.manufacturer; spool.productLine = wire.product_line
            spool.materialID = wire.material_id; spool.colorName = wire.color_name; spool.colorHex = wire.color_hex
            spool.finishRaw = wire.finish; spool.diameter = wire.diameter; spool.originalNetWeightG = wire.original_net_weight_g
            spool.currentWeightG = wire.current_weight_g; spool.emptySpoolWeightG = wire.empty_spool_weight_g
            spool.cost = wire.cost; spool.vendor = wire.vendor; spool.lotNumber = wire.lot_number; spool.batchNumber = wire.batch_number
            spool.lotFlagged = wire.lot_flagged; spool.lotNotes = wire.lot_notes; spool.notes = wire.notes
            spool.nfcTagWritten = wire.nfc_tag_written; spool.isFavorite = wire.is_favorite; spool.isArchived = wire.is_archived
            spool.amsSlotLabel = wire.ams_slot_label
            if try fetchSpool(id, context: context) == nil { context.insert(spool) }
        case "printers":
            let wire = try decoder.decode(PrinterWire.self, from: data)
            guard let id = UUID(uuidString: wire.id) else { return }
            let printer = try fetchPrinter(id, context: context) ?? PrinterDevice()
            printer.id = id; printer.manufacturer = wire.manufacturer; printer.model = wire.model; printer.customName = wire.custom_name
            printer.maxHotendTempC = wire.max_hotend_temp_c; printer.maxBedTempC = wire.max_bed_temp_c
            printer.hasEnclosure = wire.has_enclosure; printer.hasHeatedChamber = wire.has_heated_chamber
            printer.extruderRaw = wire.extruder_type; printer.amsRaw = wire.ams_type; printer.amsSlotCount = wire.ams_slot_count
            printer.totalPrintHours = wire.total_print_hours; printer.notes = wire.notes
            if try fetchPrinter(id, context: context) == nil { context.insert(printer) }
        case "profiles":
            let wire = try decoder.decode(ProfileWire.self, from: data)
            guard let id = UUID(uuidString: wire.id) else { return }
            let profile = try fetchProfile(id, context: context) ?? SlicerProfile()
            profile.id = id; profile.name = wire.name; profile.materialID = wire.material_id; profile.filamentProduct = wire.filament_product
            profile.nozzleDiameter = wire.nozzle_diameter; profile.layerHeight = wire.layer_height; profile.nozzleTemp = wire.nozzle_temp
            profile.bedTemp = wire.bed_temp; profile.printSpeed = wire.print_speed; profile.flowRatio = wire.flow_ratio
            profile.isKnownGood = wire.is_known_good; profile.successCount = wire.success_count; profile.failureCount = wire.failure_count; profile.notes = wire.notes
            if let printerID = wire.printer_id.flatMap(UUID.init(uuidString:)), let printer = try fetchPrinter(printerID, context: context) { profile.printer = printer }
            if try fetchProfile(id, context: context) == nil { context.insert(profile) }
        case "projects":
            let wire = try decoder.decode(ProjectWire.self, from: data)
            guard let id = UUID(uuidString: wire.id) else { return }
            let project = try fetchProject(id, context: context) ?? ProjectItem()
            project.id = id; project.name = wire.name; project.notes = wire.notes; project.statusRaw = wire.status
            project.createdAt = parseDate(wire.created_at) ?? project.createdAt; project.completedAt = wire.completed_at.flatMap(parseDate)
            if try fetchProject(id, context: context) == nil { context.insert(project) }
        case "prints":
            let wire = try decoder.decode(PrintWire.self, from: data)
            guard let idString = wire.id, let id = UUID(uuidString: idString) else { return }
            let print = try fetchPrint(id, context: context) ?? PrintRecord()
            print.id = id; print.name = wire.name ?? ""; print.materialID = wire.material_id ?? ""; print.date = wire.date.flatMap(parseDate) ?? print.date
            print.durationMinutes = wire.duration_minutes; print.gramsUsed = wire.grams_used; print.success = wire.success; print.categoryRaw = wire.category ?? "Final Part"; print.cost = wire.cost; print.notes = wire.notes ?? ""
            if let printerID = wire.printer_id.flatMap(UUID.init(uuidString:)) { print.printer = try fetchPrinter(printerID, context: context) }
            if let spoolID = wire.spool_id.flatMap(UUID.init(uuidString:)) { print.spool = try fetchSpool(spoolID, context: context) }
            if let profileID = wire.profile_id.flatMap(UUID.init(uuidString:)) { print.profile = try fetchProfile(profileID, context: context) }
            if let projectID = wire.project_id.flatMap(UUID.init(uuidString:)) { print.project = try fetchProject(projectID, context: context) }
            if try fetchPrint(id, context: context) == nil { context.insert(print) }
        case "maintenance":
            let wire = try decoder.decode(MaintenanceWire.self, from: data)
            guard let id = UUID(uuidString: wire.id) else { return }
            let task = try fetchMaintenance(id, context: context) ?? MaintenanceTask()
            task.id = id; task.title = wire.name; task.intervalDays = wire.interval_days; task.intervalPrintHours = wire.interval_print_hours; task.lastCompleted = wire.last_completed.flatMap(parseDate)
            if let printerID = UUID(uuidString: wire.printer_id) { task.printer = try fetchPrinter(printerID, context: context) }
            if try fetchMaintenance(id, context: context) == nil { context.insert(task) }
        default: break // transfer history has no equivalent local model; its spool update is synchronized separately.
        }
    }

    private func deleteLocal(entity: String, id: UUID, context: ModelContext) throws {
        switch entity {
        case "spools": if let value = try fetchSpool(id, context: context) { context.delete(value) }
        case "printers": if let value = try fetchPrinter(id, context: context) { context.delete(value) }
        case "profiles": if let value = try fetchProfile(id, context: context) { context.delete(value) }
        case "prints": if let value = try fetchPrint(id, context: context) { context.delete(value) }
        case "projects": if let value = try fetchProject(id, context: context) { context.delete(value) }
        case "maintenance": if let value = try fetchMaintenance(id, context: context) { context.delete(value) }
        default: break
        }
    }

    private func parseDate(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) }

    private func fetchSpool(_ id: UUID, context: ModelContext) throws -> Spool? {
        var descriptor = FetchDescriptor<Spool>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchPrinter(_ id: UUID, context: ModelContext) throws -> PrinterDevice? {
        var descriptor = FetchDescriptor<PrinterDevice>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchProfile(_ id: UUID, context: ModelContext) throws -> SlicerProfile? {
        var descriptor = FetchDescriptor<SlicerProfile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchPrint(_ id: UUID, context: ModelContext) throws -> PrintRecord? {
        var descriptor = FetchDescriptor<PrintRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchProject(_ id: UUID, context: ModelContext) throws -> ProjectItem? {
        var descriptor = FetchDescriptor<ProjectItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchMaintenance(_ id: UUID, context: ModelContext) throws -> MaintenanceTask? {
        var descriptor = FetchDescriptor<MaintenanceTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
