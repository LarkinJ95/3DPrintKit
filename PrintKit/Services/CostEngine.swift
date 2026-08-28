import Foundation

/// Print cost calculation. Pure and unit-tested.
struct CostInput {
    var filamentGrams: Double = 0
    var filamentPricePerSpool: Double = 0
    var spoolSizeGrams: Double = 1000
    var printHours: Double = 0
    var printerWatts: Double = 150
    var electricityRatePerKWh: Double = 0.15
    var machineHourlyRate: Double = 0
    var setupLaborMinutes: Double = 0
    var finishingLaborMinutes: Double = 0
    var laborRatePerHour: Double = 0
    var consumablesCost: Double = 0
    var wastePercent: Double = 0
    var failureAllowancePercent: Double = 0
    var shippingCost: Double = 0
    var packagingCost: Double = 0
    var markupPercent: Double = 0
}

struct CostResult {
    let filamentCost: Double
    let electricityCost: Double
    let machineCost: Double
    let laborCost: Double
    let consumablesCost: Double
    let wasteCost: Double
    let failureAllowanceCost: Double
    let productionCost: Double
    let suggestedPrice: Double
    let profit: Double
    let grossMarginPercent: Double
}

enum CostEngine {
    static func calculate(_ input: CostInput) -> CostResult {
        let pricePerGram = input.spoolSizeGrams > 0 ? input.filamentPricePerSpool / input.spoolSizeGrams : 0
        let filamentCost = input.filamentGrams * pricePerGram

        let electricity = input.printerWatts / 1000 * input.printHours * input.electricityRatePerKWh
        let machine = input.machineHourlyRate * input.printHours
        let labor = (input.setupLaborMinutes + input.finishingLaborMinutes) / 60 * input.laborRatePerHour

        let wasteMultiplier = 1 + max(input.wastePercent, 0) / 100
        let wasteCost = filamentCost * (wasteMultiplier - 1)

        let subtotal = filamentCost + electricity + machine + labor + input.consumablesCost
            + wasteCost + input.shippingCost + input.packagingCost
        let failureAllowance = subtotal * max(input.failureAllowancePercent, 0) / 100
        let production = subtotal + failureAllowance

        let price = production * (1 + max(input.markupPercent, 0) / 100)
        let profit = price - production
        let margin = price > 0 ? profit / price * 100 : 0

        return CostResult(
            filamentCost: filamentCost,
            electricityCost: electricity,
            machineCost: machine,
            laborCost: labor,
            consumablesCost: input.consumablesCost,
            wasteCost: wasteCost,
            failureAllowanceCost: failureAllowance,
            productionCost: production,
            suggestedPrice: price,
            profit: profit,
            grossMarginPercent: margin
        )
    }
}
