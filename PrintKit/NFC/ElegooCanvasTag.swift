import Foundation

/// Encodes the documented, writable NTAG213 user-memory layout used by the
/// ELEGOO CANVAS filament system. This intentionally never writes tag UID,
/// lock, or password pages.
struct ElegooCanvasTag {
    static let firstWritablePage = 4
    static let lastWritablePage = 44

    private var bytes: [UInt8]

    init(spool: Spool) {
        // Baseline layout from ELEGOO's published tag guide. Pages 0–3 (UID,
        // capability container, and lock bytes) are not included in writes.
        bytes = [
            0x53,0x44,0xE5,0x7A,0x01,0xA0,0x00,0x04,0xA5,0x48,0x00,0x00,0xE1,0x10,0x12,0x00,
            0x01,0x03,0xA0,0x0C,0x34,0x03,0x0F,0xD1,0x01,0x0B,0x55,0x02,0x65,0x6C,0x65,0x67,
            0x6F,0x6F,0x2E,0x63,0x6F,0x6D,0xFE,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x36,0xEE,0xEE,0xEE,0xEE,0x00,0x00,0x00,0x00,0x80,0x76,0x65,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0xFF,0x00,0xBE,0x00,0xE6,0x00,0x00,0x00,0x00,0x00,0xAF,0x03,0xE8,
            0x25,0x01,0xC8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0xBD,0x04,0x00,0x00
        ]

        let material = MaterialLibrary.shared.material(for: spool.materialID)
        let (family, subtype) = Self.materialCodes(for: spool.materialID)
        writeUInt32(family, at: 0x48)
        writeUInt16(subtype, at: 0x4C)
        writeColor(spool.colorHex, at: 0x50)
        writeUInt16(UInt16(clamping: material?.nozzleMin ?? 190), at: 0x54)
        writeUInt16(UInt16(clamping: material?.nozzleMax ?? 220), at: 0x56)
        writeUInt16(UInt16(clamping: Int((spool.diameter * 100).rounded())), at: 0x5C)
        writeUInt16(UInt16(clamping: Int(spool.currentWeightG.rounded())), at: 0x5E)
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: spool.purchaseDate ?? Date()) % 100
        let month = calendar.component(.month, from: spool.purchaseDate ?? Date())
        bytes[0x60] = bcd(year)
        bytes[0x61] = bcd(month)
    }

    /// Four-byte writes for user memory only (pages 4 through 44).
    var writes: [(page: UInt8, bytes: Data)] {
        (Self.firstWritablePage...Self.lastWritablePage).map { page in
            let offset = page * 4
            return (UInt8(page), Data(bytes[offset..<(offset + 4)]))
        }
    }

    var verificationBytes: Data { Data(bytes[64..<80]) }

    static func payload(identifier: Data, primary: Data, details: Data, dimensions: Data) -> SpoolTagPayload? {
        guard primary.count >= 16, details.count >= 16, dimensions.count >= 4,
              primary[0] == 0x36, primary[1...4] == Data([0xEE, 0xEE, 0xEE, 0xEE]) else { return nil }
        let family = UInt32(primary[8]) << 24 | UInt32(primary[9]) << 16 | UInt32(primary[10]) << 8 | UInt32(primary[11])
        let subtype = UInt16(primary[12]) << 8 | UInt16(primary[13])
        let hex = String(format: "#%02X%02X%02X", details[0], details[1], details[2])
        let diameter = Double(UInt16(dimensions[0]) << 8 | UInt16(dimensions[1])) / 100
        let weight = Double(UInt16(dimensions[2]) << 8 | UInt16(dimensions[3]))
        return SpoolTagPayload(schema: SpoolTagPayload.schemaID, version: 1, spoolID: stableID(for: identifier), manufacturer: "ELEGOO", material: materialID(family: family, subtype: subtype), product: "CANVAS RFID tag", color: hex, colorHex: hex, diameter: diameter, originalWeight: weight, remainingWeight: weight)
    }

    private mutating func writeUInt16(_ value: UInt16, at offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }

    private mutating func writeUInt32(_ value: UInt32, at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(value & 0xFF)
    }

    private mutating func writeColor(_ hex: String, at offset: Int) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return }
        bytes[offset] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8(value & 0xFF)
    }

    private func bcd(_ value: Int) -> UInt8 {
        UInt8(((value / 10) << 4) | (value % 10))
    }

    private static func materialCodes(for materialID: String) -> (UInt32, UInt16) {
        let id = materialID.lowercased()
        if id.contains("petg") { return (0x8069_8471, id.contains("cf") ? 0x0101 : id.contains("gf") ? 0x0102 : 0x0100) }
        if id.contains("abs") { return (0x0065_6683, 0x0200) }
        if id.contains("tpu") { return (0x0084_8085, 0x0300) }
        if id.contains("nylon") || id.hasPrefix("pa") { return (0x0000_8065, id.contains("cf") ? 0x0401 : 0x0400) }
        if id.contains("asa") { return (0x0065_8365, 0x0800) }
        if id.contains("pc") { return (0x0000_8067, 0x0600) }
        if id.contains("pva") { return (0x0080_8665, 0x0700) }
        return (0x0080_7665, id.contains("plus") || id.contains("+") ? 0x0001 : 0x0000)
    }

    private static func stableID(for identifier: Data) -> UUID {
        let hex = identifier.map { String(format: "%02x", $0) }.joined()
        let padded = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-0000-\(padded.prefix(4))-\(padded.suffix(12))") ?? UUID()
    }

    private static func materialID(family: UInt32, subtype: UInt16) -> String {
        switch family {
        case 0x8069_8471: return subtype == 0x0101 ? "petg-cf" : subtype == 0x0102 ? "petg-gf" : "petg"
        case 0x0065_6683: return "abs"
        case 0x0084_8085: return "tpu"
        case 0x0000_8065: return subtype == 0x0401 ? "pa-cf" : "pa"
        case 0x0065_8365: return "asa"
        case 0x0000_8067: return "pc"
        case 0x0080_8665: return "pva"
        default: return subtype == 0x0001 ? "pla-plus" : "pla"
        }
    }
}
