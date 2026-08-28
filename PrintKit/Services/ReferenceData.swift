import Foundation

// MARK: - Fastener reference (generic workshop reference values — editable in-app later)

struct FastenerRow: Identifiable {
    let id: String
    let designation: String
    let clearanceClose: Double?   // mm
    let clearanceNormal: Double?
    let clearanceLoose: Double?
    let pilotHole: Double?        // mm (for thread-forming / tapping in plastic)
    let insertHole: Double?       // mm for common heat-set inserts (generic reference)
    let notes: String
}

enum FastenerReference {
    /// Generic metric reference values. Always labeled as reference, not
    /// manufacturer specification.
    static let metric: [FastenerRow] = [
        .init(id: "m2", designation: "M2", clearanceClose: 2.2, clearanceNormal: 2.4, clearanceLoose: 2.6, pilotHole: 1.6, insertHole: 3.2, notes: "Insert hole suits common M2 heat-set inserts."),
        .init(id: "m2.5", designation: "M2.5", clearanceClose: 2.7, clearanceNormal: 2.9, clearanceLoose: 3.1, pilotHole: 2.1, insertHole: 3.6, notes: ""),
        .init(id: "m3", designation: "M3", clearanceClose: 3.2, clearanceNormal: 3.4, clearanceLoose: 3.6, pilotHole: 2.5, insertHole: 4.2, notes: "Most common for printed assemblies; Voron-style inserts typically 4.0–4.2 mm."),
        .init(id: "m4", designation: "M4", clearanceClose: 4.3, clearanceNormal: 4.5, clearanceLoose: 4.8, pilotHole: 3.3, insertHole: 5.6, notes: ""),
        .init(id: "m5", designation: "M5", clearanceClose: 5.3, clearanceNormal: 5.5, clearanceLoose: 5.8, pilotHole: 4.2, insertHole: 6.4, notes: ""),
        .init(id: "m6", designation: "M6", clearanceClose: 6.4, clearanceNormal: 6.6, clearanceLoose: 7.0, pilotHole: 5.0, insertHole: 8.0, notes: ""),
        .init(id: "m8", designation: "M8", clearanceClose: 8.4, clearanceNormal: 9.0, clearanceLoose: 10.0, pilotHole: 6.8, insertHole: 9.7, notes: "")
    ]

    static let imperial: [FastenerRow] = [
        .init(id: "4-40", designation: "#4-40", clearanceClose: 3.0, clearanceNormal: 3.2, clearanceLoose: 3.4, pilotHole: 2.3, insertHole: 4.0, notes: ""),
        .init(id: "6-32", designation: "#6-32", clearanceClose: 3.6, clearanceNormal: 3.8, clearanceLoose: 4.0, pilotHole: 2.8, insertHole: 4.8, notes: ""),
        .init(id: "8-32", designation: "#8-32", clearanceClose: 4.4, clearanceNormal: 4.6, clearanceLoose: 4.9, pilotHole: 3.4, insertHole: 5.5, notes: ""),
        .init(id: "10-24", designation: "#10-24", clearanceClose: 5.1, clearanceNormal: 5.3, clearanceLoose: 5.6, pilotHole: 3.9, insertHole: 6.3, notes: ""),
        .init(id: "1/4-20", designation: "1/4-20", clearanceClose: 6.7, clearanceNormal: 7.0, clearanceLoose: 7.4, pilotHole: 5.1, insertHole: 8.0, notes: "")
    ]

    /// Common bearing bores (printed parts typically need light clearance).
    struct BearingRow: Identifiable {
        let id: String
        let designation: String
        let boreMM: Double
        let suggestedBore: Double   // modeled hole for a light press/slip in printed parts
        let notes: String
    }

    static let bearings: [BearingRow] = [
        .init(id: "608", designation: "608 (8×22×7)", boreMM: 22, suggestedBore: 22.2, notes: "Skate/spool-holder standard."),
        .init(id: "623", designation: "623 (3×10×4)", boreMM: 10, suggestedBore: 10.1, notes: ""),
        .init(id: "625", designation: "625 (5×16×5)", boreMM: 16, suggestedBore: 16.15, notes: ""),
        .init(id: "6800", designation: "6800 (10×19×5)", boreMM: 19, suggestedBore: 19.15, notes: ""),
        .init(id: "lm8uu", designation: "LM8UU linear", boreMM: 15, suggestedBore: 15.2, notes: "Clamp-style mounts preferred over press fit.")
    ]
}

// MARK: - Thread reference

struct ThreadNote: Identifiable {
    let id: String
    let title: String
    let body: String
}

enum ThreadReference {
    static let entries: [ThreadNote] = [
        .init(id: "printed", title: "Printed Threads",
              body: "Model threads with at least 0.15–0.25 mm radial clearance for a working fit. Print threads vertically for the cleanest profile. Use thread profiles with a flat root where possible; sharp V-threads concentrate stress. For M6 and below, heat-set inserts or captured nuts are usually stronger."),
        .init(id: "heatset", title: "Heat-Set Inserts",
              body: "Use the insert manufacturer's hole recommendation where available; generic reference: hole ≈ insert OD − 0.1–0.3 mm for a thermal press fit. Install with a soldering-iron tip at low heat, press straight, and let the joint cool before loading. Boss OD should be ≥ 2× insert OD."),
        .init(id: "inserts", title: "Threaded Inserts (General)",
              body: "Keep insert axis perpendicular to the surface. Leave 1–2 thread pitches of clearance depth below the insert. For repeated assembly, prefer metal inserts over printed threads."),
        .init(id: "captured", title: "Captured Nuts",
              body: "Model the nut trap with the flat-to-flat dimension + 0.2–0.4 mm. Add a pause or an access channel for insertion. Orient the trap so the screw load pulls the nut against a wall, not out of the slot.")
    ]
}
