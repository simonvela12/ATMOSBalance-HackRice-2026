import Foundation
import FinancialCore

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!

func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

func money(_ value: Double) -> String {
    String(format: "$%.2f", value)
}

let asOf = date(2026, 9, 12)
let horizon = date(2026, 11, 30)

let profile = FinancialProfile(
    currentCash: 8000,
    asOfDate: asOf,
    personalReserveSteps: [
        PersonalReserveStep(
            effectiveDate: asOf,
            minimumCash: 7000,
            note: "User-confirmed minimum runway"
        )
    ],
    incomeEvents: [
        IncomeEvent(
            amount: 1000,
            date: date(2026, 11, 1),
            source: "Expected income",
            type: .recurring
        )
    ],
    expenseEvents: [
        ExpenseEvent(
            amount: 500,
            date: date(2026, 11, 15),
            category: "Essential expenses"
        )
    ],
    spendingPolicy: SpendingPolicy(
        lookbackWeeks: 6,
        bufferWeeks: 0,
        manualMinimumBuffer: 250
    )
)

do {
    let target = try FinancialEngine.forecast(
        profile: profile,
        targetDate: horizon,
        calendar: calendar
    )

    let safeNow = try FinancialEngine.safeToSpend(
        profile: profile,
        from: asOf,
        through: horizon,
        calendar: calendar
    )

    let ticket = try FinancialEngine.assessPurchase(
        profile: profile,
        amount: 450,
        purchaseDate: date(2026, 9, 15),
        planningHorizon: horizon,
        calendar: calendar
    )

    print("=== FinancialCore demo ===")
    print("Projected cash on Nov 30: \(money(target.projectedCash))")
    print("Headroom on Nov 30:       \(money(target.recommendedHeadroom))")
    print("Safe to spend today:      \(money(safeNow))")
    print("$450 purchase status:     \(ticket.status.rawValue)")
    print("Headroom after purchase at tightest point: \(money(ticket.minimumRecommendedHeadroomAfterPurchase))")
    print("\nNote: target-date headroom and safe-to-spend-today are different because the engine checks the entire cash path, not only the final date.")
} catch {
    fputs("FinancialCore demo failed: \(error)\n", stderr)
    exit(1)
}
