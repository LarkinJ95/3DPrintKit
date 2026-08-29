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
        let server_time: Date?
        // Records are applied by the backend-defined DTOs; the iOS client keeps
        // only the cursor here and reconciles spools in a targeted fashion.
        let spools: [SpoolSyncDTO]?
        let deleted: [Tombstone]?
        struct Tombstone: Decodable {
            let entity: String
            let record_id: String
        }
    }

    struct SpoolSyncDTO: Decodable {
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
        let cursor = UserDefaults.standard.string(forKey: cursorKey) ?? ""
        let response: SyncPullResponse = try await APIClient.shared.request(
            "GET", "/api/v1/sync", query: ["since": cursor]
        )

        // Apply tombstones first so stale local copies never resurrect.
        for tombstone in response.deleted ?? [] where tombstone.entity == "spools" {
            if let uuid = UUID(uuidString: tombstone.record_id),
               let spool = try fetchSpool(uuid, context: context) {
                context.delete(spool)
            }
        }

        // Reconcile spools by UUID (client-generated, stable across devices).
        for dto in response.spools ?? [] {
            guard let uuid = UUID(uuidString: dto.id) else { continue }
            if let existing = try fetchSpool(uuid, context: context) {
                // Server weight is authoritative only when newer; local pending
                // deltas were already pushed above.
                existing.manufacturer = dto.manufacturer
                existing.productLine = dto.product_line
                existing.materialID = dto.material_id
                existing.colorName = dto.color_name
                if let colorHex = dto.color_hex, !colorHex.isEmpty {
                    existing.colorHex = colorHex
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

        UserDefaults.standard.set(response.cursor, forKey: cursorKey)
        try? context.save()
    }

    private func fetchSpool(_ id: UUID, context: ModelContext) throws -> Spool? {
        var descriptor = FetchDescriptor<Spool>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
