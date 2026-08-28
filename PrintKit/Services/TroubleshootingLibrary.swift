import Foundation

struct TroubleshootingCause: Identifiable {
    let id = UUID()
    let cause: String
    let likelihood: Int      // 1...5
    let fix: String
}

struct TroubleshootingIssue: Identifiable {
    let id: String
    let title: String
    let symptoms: String
    let questions: [String]
    let causes: [TroubleshootingCause]
}

/// Offline troubleshooting knowledge base. Diagnoses are ranked *likely
/// causes*, never certainties.
enum TroubleshootingLibrary {
    static let issues: [TroubleshootingIssue] = [
        .init(id: "stringing", title: "Stringing / Oozing",
              symptoms: "Fine hairs or wisps of plastic between separate features.",
              questions: ["Which material?", "What nozzle temperature?", "What retraction distance and speed?", "Is the filament dry?"],
              causes: [
                .init(cause: "Nozzle temperature too high", likelihood: 4, fix: "Lower nozzle temperature 5–10 °C and run a temperature tower."),
                .init(cause: "Insufficient retraction", likelihood: 4, fix: "Increase retraction 0.5–1 mm (direct) or 1–2 mm (Bowden); raise retraction speed."),
                .init(cause: "Wet filament", likelihood: 3, fix: "Dry the spool per the material's reference drying guidance."),
                .init(cause: "Travel moves too slow", likelihood: 2, fix: "Increase travel speed and enable combing/wipe.")]),
        .init(id: "warping", title: "Warping",
              symptoms: "Corners lift off the bed; large prints curl upward.",
              questions: ["Which material?", "Is the printer enclosed?", "What bed temperature and surface?"],
              causes: [
                .init(cause: "Bed temperature too low", likelihood: 4, fix: "Raise bed temperature within the material's recommended range."),
                .init(cause: "Drafts / no enclosure", likelihood: 4, fix: "Enclose the printer or move it away from drafts and air conditioning."),
                .init(cause: "Poor first-layer adhesion", likelihood: 3, fix: "Clean the plate, re-level, and use the recommended adhesive for the material."),
                .init(cause: "Too much part cooling", likelihood: 3, fix: "Reduce fan speed for high-temperature materials like ABS/ASA.")]),
        .init(id: "layer-separation", title: "Layer Separation / Splitting",
              symptoms: "Layers crack apart, especially on tall or stressed parts.",
              questions: ["Which material?", "Nozzle temperature?", "Is cooling fan at 100%?"],
              causes: [
                .init(cause: "Nozzle temperature too low", likelihood: 4, fix: "Raise temperature 5–10 °C to improve layer bonding."),
                .init(cause: "Excessive cooling", likelihood: 3, fix: "Reduce fan speed; high-temp materials often need 0–30% fan."),
                .init(cause: "Printing too fast for the hotend", likelihood: 3, fix: "Check volumetric flow against the hotend's known limit.")]),
        .init(id: "under-extrusion", title: "Under-Extrusion",
              symptoms: "Gaps in walls, thin or missing extrusion, weak infill.",
              questions: ["Clicking extruder?", "What nozzle size and flow rate?", "Recent nozzle change?"],
              causes: [
                .init(cause: "Partial nozzle clog", likelihood: 4, fix: "Cold pull or replace the nozzle; check for degraded PTFE in the hotend."),
                .init(cause: "Flow demand above hotend capacity", likelihood: 4, fix: "Reduce speed or layer height; measure the hotend's maximum volumetric flow."),
                .init(cause: "Tangled or binding spool", likelihood: 3, fix: "Check the spool path and feed resistance."),
                .init(cause: "Worn extruder gears", likelihood: 2, fix: "Inspect drive gears for filament dust and wear.")]),
        .init(id: "over-extrusion", title: "Over-Extrusion",
              symptoms: "Bulging walls, ridges on top surfaces, dimensional oversize.",
              questions: ["Calibrated flow for this filament?", "What flow ratio is set?"],
              causes: [
                .init(cause: "Flow ratio too high", likelihood: 5, fix: "Calibrate flow; many filaments land between 0.94 and 0.98."),
                .init(cause: "Incorrect filament diameter setting", likelihood: 2, fix: "Verify the slicer diameter matches the spool (1.75 vs 2.85 mm).")]),
        .init(id: "elephant-foot", title: "Elephant Foot",
              symptoms: "First few layers bulge outward beyond the intended outline.",
              questions: ["Bed temperature?", "First layer height?"],
              causes: [
                .init(cause: "Bed too hot", likelihood: 4, fix: "Lower bed temperature 5–10 °C."),
                .init(cause: "First layer over-compressed", likelihood: 3, fix: "Raise Z-offset slightly or enable the slicer's elephant-foot compensation.")]),
        .init(id: "first-layer", title: "Poor First Layer",
              symptoms: "Patchy, lifted, or smashed first layer; parts won't stick.",
              questions: ["When was the plate last cleaned?", "Auto bed leveling used?"],
              causes: [
                .init(cause: "Dirty build plate", likelihood: 5, fix: "Wash with dish soap and water; wipe with isopropyl alcohol."),
                .init(cause: "Incorrect Z-offset", likelihood: 4, fix: "Re-run first-layer calibration; adjust in 0.02–0.05 mm steps."),
                .init(cause: "Unlevel bed", likelihood: 3, fix: "Re-run bed leveling; check for a warped plate.")]),
        .init(id: "layer-shift", title: "Layer Shifting",
              symptoms: "Layers suddenly offset in X or Y mid-print.",
              questions: ["Belt condition and tension?", "Any collisions with the print?"],
              causes: [
                .init(cause: "Loose or worn belts", likelihood: 4, fix: "Re-tension belts; inspect for missing teeth."),
                .init(cause: "Mechanical collision", likelihood: 3, fix: "Watch for curled overhangs catching the nozzle; enable Z-hop."),
                .init(cause: "Speeds/acceleration too high", likelihood: 3, fix: "Reduce travel speed and acceleration.")]),
        .init(id: "ringing", title: "Ringing / Ghosting",
              symptoms: "Repeating ripples after corners or holes.",
              questions: ["Is input shaping tuned?", "How rigid is the printer mounting?"],
              causes: [
                .init(cause: "Acceleration too high for frame rigidity", likelihood: 4, fix: "Lower acceleration and outer-wall speed."),
                .init(cause: "Input shaping mistuned", likelihood: 3, fix: "Re-run resonance/input-shaping calibration."),
                .init(cause: "Loose mechanical parts", likelihood: 2, fix: "Check frame fasteners, belts, and print-head play.")]),
        .init(id: "z-banding", title: "Z-Banding",
              symptoms: "Repeating horizontal ridges at regular intervals.",
              questions: ["Lead screw lubricated?", "Band spacing match lead-screw pitch?"],
              causes: [
                .init(cause: "Lead screw issue", likelihood: 4, fix: "Clean and lubricate lead screws; check for bent screws or binding."),
                .init(cause: "Inconsistent extrusion temperature", likelihood: 2, fix: "PID-tune the hotend.")]),
        .init(id: "blobs-zits", title: "Blobs and Zits",
              symptoms: "Small bumps on outer walls, often at layer changes.",
              questions: ["Seam position settings?", "Retraction tuning?"],
              causes: [
                .init(cause: "Seam placement", likelihood: 4, fix: "Move the seam to a hidden corner; enable seam hiding/alignment."),
                .init(cause: "Retraction/deretraction pressure", likelihood: 3, fix: "Tune retraction and pressure advance; wipe on retract.")]),
        .init(id: "clog", title: "Clogged Nozzle",
              symptoms: "No extrusion despite the extruder driving filament.",
              questions: ["Filled filament recently used?", "Cold pull attempted?"],
              causes: [
                .init(cause: "Debris or degraded filament", likelihood: 4, fix: "Cold pull with cleaning filament or nylon; replace the nozzle if unresolved."),
                .init(cause: "Heat creep", likelihood: 3, fix: "Check the hotend fan and heat-break for softened filament above the melt zone.")]),
        .init(id: "heat-creep", title: "Heat Creep",
              symptoms: "Extrusion stalls mid-print, often on slow prints or high chamber temps.",
              questions: ["Hotend fan working?", "Printing slowly with high temperature?"],
              causes: [
                .init(cause: "Hotend cooling insufficient", likelihood: 4, fix: "Verify the hotend fan runs at full speed; clear dust from the heatsink."),
                .init(cause: "Chamber too hot for the material", likelihood: 3, fix: "Vent the enclosure for PLA/PETG.")]),
        .init(id: "bridging", title: "Poor Bridging",
              symptoms: "Sagging, droopy strands across open spans.",
              questions: ["Bridge fan speed?", "Bridge length?"],
              causes: [
                .init(cause: "Insufficient cooling", likelihood: 4, fix: "Raise bridge fan speed to 100% for PLA; reduce bridge flow slightly."),
                .init(cause: "Temperature too high", likelihood: 3, fix: "Lower nozzle temperature 5 °C.")]),
        .init(id: "overhangs", title: "Sagging Overhangs",
              symptoms: "Rough, curled, or drooping surfaces beyond ~50°.",
              questions: ["Overhang angle?", "Fan speed at overhangs?"],
              causes: [
                .init(cause: "Cooling too low", likelihood: 4, fix: "Increase fan; slow down overhang speed."),
                .init(cause: "Layer height too large for the angle", likelihood: 2, fix: "Reduce layer height on steep overhangs.")]),
        .init(id: "weak-parts", title: "Weak Parts",
              symptoms: "Parts snap easily, especially along layer lines.",
              questions: ["Wall count?", "Nozzle temperature?", "Material choice?"],
              causes: [
                .init(cause: "Too few walls / low temperature", likelihood: 4, fix: "Add walls, raise nozzle temperature, reduce cooling."),
                .init(cause: "Wrong material for the load", likelihood: 3, fix: "Use the material assistant — e.g. PETG/PC/PA for toughness over PLA."),
                .init(cause: "Wet filament", likelihood: 3, fix: "Dry hygroscopic materials before printing.")]),
        .init(id: "wet-filament", title: "Wet Filament",
              symptoms: "Popping sounds, steam, rough surface, stringing, weak parts.",
              questions: ["Material's hygroscopicity?", "How long exposed to air?"],
              causes: [
                .init(cause: "Moisture absorption", likelihood: 5, fix: "Dry per the material's reference guidance; store in a dry box with desiccant.")]),
        .init(id: "grinding", title: "Extruder Grinding / Clicking",
              symptoms: "Drive gear chews the filament; clicking from the extruder.",
              questions: ["Any downstream restriction?", "Nozzle temperature?"],
              causes: [
                .init(cause: "Downstream blockage", likelihood: 4, fix: "Clear the nozzle/heat-break; check for a gap between nozzle and tube."),
                .init(cause: "Flow demand too high", likelihood: 3, fix: "Reduce speed; verify the hotend's flow limit."),
                .init(cause: "Gear tension wrong", likelihood: 2, fix: "Adjust idler tension; clean gear teeth.")]),
        .init(id: "gaps", title: "Gaps Between Walls / Top Layers",
              symptoms: "Visible gaps between perimeters or in solid top layers.",
              questions: ["Flow calibrated?", "Line width vs nozzle size?"],
              causes: [
                .init(cause: "Under-extrusion", likelihood: 4, fix: "Calibrate flow; check for partial clogs."),
                .init(cause: "Line width mismatch", likelihood: 2, fix: "Keep line width within 100–150% of nozzle diameter.")]),
        .init(id: "support-failure", title: "Support Failure",
              symptoms: "Supports collapse or fuse permanently to the part.",
              questions: ["Support interface settings?", "Support material pairing?"],
              causes: [
                .init(cause: "Interface gap wrong", likelihood: 4, fix: "Adjust support Z distance; try interface layers."),
                .init(cause: "Incompatible support material", likelihood: 2, fix: "Use a listed support pairing (e.g. PVA/BVOH for PLA) when available.")]),
        .init(id: "adhesion", title: "Bed Adhesion Problems",
              symptoms: "Prints detach mid-print or slide around.",
              questions: ["Plate type and material?", "Cleaning routine?"],
              causes: [
                .init(cause: "Contaminated surface", likelihood: 5, fix: "Wash with dish soap; avoid touching the print area."),
                .init(cause: "Wrong surface for the material", likelihood: 3, fix: "Check the material's recommended bed surfaces; use glue stick/ adhesive where listed."),
                .init(cause: "Bed temperature too low", likelihood: 3, fix: "Raise bed temperature within range.")]),
        .init(id: "rough-top", title: "Rough Top Surface",
              symptoms: "Pillowed, scarred, or rough top layers.",
              questions: ["Top layer count?", "Ironing enabled?"],
              causes: [
                .init(cause: "Too few top layers / low infill", likelihood: 4, fix: "Add top layers or raise infill to support the skin."),
                .init(cause: "Over-extrusion", likelihood: 2, fix: "Calibrate flow; consider ironing for cosmetic tops.")]),
        .init(id: "dimensional", title: "Poor Dimensional Accuracy",
              symptoms: "Parts consistently too large or small; holes too tight.",
              questions: ["Measured with calipers?", "Same error on all axes?"],
              causes: [
                .init(cause: "Material shrinkage", likelihood: 4, fix: "Run the shrinkage/scale compensation tool per axis; save the profile."),
                .init(cause: "Hole shrinkage", likelihood: 3, fix: "Use the hole compensation tool; design with tested tolerance values.")])
    ]

    static func issue(for id: String) -> TroubleshootingIssue? {
        issues.first { $0.id == id }
    }
}
