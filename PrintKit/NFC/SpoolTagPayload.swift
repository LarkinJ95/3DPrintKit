import Foundation

/// Compact, versioned NFC/QR payload identifying a 3DPrintKit spool.
///
/// Backward compatibility: the decoder tolerates unknown fields and missing
/// optional values; `version` gates future format changes.
struct SpoolTagPayload: Codable, Equatable, Identifiable {
    let schema: String          // "3dprintkit.spool"
    let version: Int            // 1
    let spoolID: UUID
    var manufacturer: String?
    var material: String?
    var product: String?
    var color: String?
    var colorHex: String?
    var diameter: Double?
    var originalWeight: Double?
    var remainingWeight: Double?

    static let schemaID = "3dprintkit.spool"
    private static let legacySchemaID = "printkit.spool"

    var id: UUID { spoolID }

    init(spool: Spool) {
        schema = Self.schemaID
        version = 1
        spoolID = spool.id
        manufacturer = spool.manufacturer.isEmpty ? nil : spool.manufacturer
        material = spool.materialID
        product = spool.productLine.isEmpty ? nil : spool.productLine
        color = spool.colorName.isEmpty ? nil : spool.colorName
        colorHex = spool.colorHex
        diameter = spool.diameter
        originalWeight = spool.originalNetWeightG
        remainingWeight = spool.currentWeightG
    }

    init(schema: String, version: Int, spoolID: UUID,
         manufacturer: String? = nil, material: String? = nil, product: String? = nil,
         color: String? = nil, colorHex: String? = nil, diameter: Double? = nil,
         originalWeight: Double? = nil, remainingWeight: Double? = nil) {
        self.schema = schema
        self.version = version
        self.spoolID = spoolID
        self.manufacturer = manufacturer
        self.material = material
        self.product = product
        self.color = color
        self.colorHex = colorHex
        self.diameter = diameter
        self.originalWeight = originalWeight
        self.remainingWeight = remainingWeight
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]   // compact, deterministic
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> SpoolTagPayload? {
        guard let payload = try? JSONDecoder().decode(SpoolTagPayload.self, from: data),
              [schemaID, legacySchemaID].contains(payload.schema),
              payload.version <= 1 else { return nil }
        return payload
    }

    /// QR codes carry the same identity as NFC: a printkit:// URL wrapping the UUID,
    /// with the JSON payload as fallback for cross-tool readability.
    var qrString: String { "printkit://spool/\(spoolID.uuidString)" }

    static func decodeQR(_ string: String) -> UUID? {
        for prefix in ["3dprintkit://spool/", "printkit://spool/"] {
            if string.hasPrefix(prefix),
               let uuid = UUID(uuidString: String(string.dropFirst(prefix.count))) {
                return uuid
            }
        }
        if let data = string.data(using: .utf8), let payload = decode(data) {
            return payload.spoolID
        }
        return UUID(uuidString: string)   // bare UUID fallback
    }
}
