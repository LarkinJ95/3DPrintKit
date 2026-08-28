import Foundation

/// Pure filament geometry / inventory math. All functions are deterministic
/// and unit-tested.
enum FilamentMath {

    /// Cross-sectional area of the filament in mm^2.
    static func crossSectionAreaMM2(diameterMM: Double) -> Double {
        let r = diameterMM / 2
        return .pi * r * r
    }

    /// Volume of a given mass of filament in cm^3.
    static func volumeCM3(grams: Double, densityGcm3: Double) -> Double {
        guard densityGcm3 > 0 else { return 0 }
        return grams / densityGcm3
    }

    /// Length in meters for a given mass of filament.
    static func gramsToMeters(_ grams: Double, diameterMM: Double, densityGcm3: Double) -> Double {
        let volumeMM3 = volumeCM3(grams: grams, densityGcm3: densityGcm3) * 1000
        let area = crossSectionAreaMM2(diameterMM: diameterMM)
        guard area > 0 else { return 0 }
        return volumeMM3 / area / 1000
    }

    /// Mass in grams for a given length in meters.
    static func metersToGrams(_ meters: Double, diameterMM: Double, densityGcm3: Double) -> Double {
        let volumeMM3 = meters * 1000 * crossSectionAreaMM2(diameterMM: diameterMM)
        return volumeMM3 / 1000 * densityGcm3
    }

    /// Remaining grams from a scale reading.
    static func netGrams(grossGrams: Double, emptySpoolGrams: Double) -> Double {
        max(grossGrams - emptySpoolGrams, 0)
    }

    /// Volumetric flow in mm^3/s.
    static func volumetricFlow(lineWidthMM: Double, layerHeightMM: Double, speedMMs: Double) -> Double {
        lineWidthMM * layerHeightMM * speedMMs
    }

    /// Maximum print speed for a target volumetric flow.
    static func maxSpeed(targetFlowMm3s: Double, lineWidthMM: Double, layerHeightMM: Double) -> Double {
        let denom = lineWidthMM * layerHeightMM
        guard denom > 0 else { return 0 }
        return targetFlowMm3s / denom
    }

    /// Number of full prints possible from a spool, keeping a configurable
    /// reserve percentage of the *original* spool weight aside.
    static func depletionPrints(remainingG: Double, perPrintG: Double, reservePercent: Double, originalG: Double) -> Int {
        guard perPrintG > 0 else { return 0 }
        let reserve = originalG * reservePercent / 100
        let usable = max(remainingG - reserve, 0)
        return Int(usable / perPrintG)
    }

    /// Shrinkage compensation: recommended scale factor per axis.
    static func scaleCompensation(designed: Double, measured: Double) -> (error: Double, percentError: Double, scaleFactor: Double) {
        guard designed > 0 else { return (0, 0, 1) }
        let error = measured - designed
        let pct = error / designed * 100
        let factor = designed / measured
        return (error, pct, factor.isFinite && factor > 0 ? factor : 1)
    }

    /// Hole compensation: modeled-hole correction to reach the designed diameter.
    static func holeCompensation(designedMM: Double, measuredMM: Double) -> Double {
        designedMM - measuredMM
    }
}
