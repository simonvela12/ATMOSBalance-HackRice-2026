import Foundation
import Testing
@testable import Test

struct WhatIfTests {
    private let engine = WhatIfEngine()

    @Test func parsesPurchaseAmountAndRelativeDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!

        let scenario = try engine.parse(
            question: "Can I buy F1 tickets for $450 next month?",
            now: now,
            calendar: calendar
        )

        #expect(scenario.amount == 450)
        #expect(scenario.name.lowercased().contains("f1 tickets"))
        #expect(scenario.intendedDate != nil)
    }

    @Test func marksAffordablePurchaseSafe() throws {
        let summary = FinancialSummary(
            currentCash: 8_000,
            protectedCash: 7_000,
            safeToSpendThroughNovember: 1_250,
            safeToSpendThisWeek: 100
        )

        let scenario = WhatIfScenario(type: .purchase, name: "F1 ticket", amount: 450, intendedDate: nil)
        let result = engine.evaluate(scenario: scenario, summary: summary)

        #expect(result.status == .safe)
        #expect(result.remainingAfterPurchase == 800)
    }

    @Test func marksOversizedPurchaseWait() throws {
        let summary = FinancialSummary(
            currentCash: 8_000,
            protectedCash: 7_000,
            safeToSpendThroughNovember: 1_250,
            safeToSpendThisWeek: 100
        )

        let scenario = WhatIfScenario(type: .purchase, name: "Laptop", amount: 1_500, intendedDate: nil)
        let result = engine.evaluate(scenario: scenario, summary: summary)

        #expect(result.status == .wait)
        #expect(result.remainingAfterPurchase == -250)
        #expect(result.recommendedDate != nil)
    }

    @Test func rejectsQuestionWithoutAmount() {
        #expect(throws: WhatIfEngine.EngineError.missingAmount) {
            try engine.parse(question: "Can I buy F1 tickets next month?")
        }
    }
}
