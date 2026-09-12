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

    @Test func marksAffordablePurchaseSafeWithoutHurtingGoals() throws {
        let summary = FinancialSummary(
            currentCash: 8_000,
            protectedCash: 7_000,
            safeToSpendThroughNovember: 1_250,
            safeToSpendThisWeek: 100
        )

        let goal = FinancialGoal(
            name: "Miami Trip",
            targetAmount: 900,
            currentSaved: 550,
            targetDate: Date(),
            priority: .high,
            plannedMonthlyContribution: 200
        )

        let scenario = WhatIfScenario(type: .purchase, name: "F1 ticket", amount: 450, intendedDate: nil)
        let result = engine.evaluate(scenario: scenario, summary: summary, goals: [goal])

        #expect(result.status == .safe)
        #expect(result.remainingAfterPurchase == 800)
        #expect(result.goalImpacts.first?.impactLevel == .unaffected)
    }

    @Test func purchaseCanBecomeTradeOffByDelayingMiami() throws {
        let calendar = Calendar(identifier: .gregorian)
        let targetDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14))!
        let summary = FinancialSummary(
            currentCash: 8_000,
            protectedCash: 7_000,
            safeToSpendThroughNovember: 1_250,
            safeToSpendThisWeek: 100
        )

        let miami = FinancialGoal(
            name: "Miami Trip",
            targetAmount: 900,
            currentSaved: 550,
            targetDate: targetDate,
            priority: .high,
            plannedMonthlyContribution: 200,
            isProtected: false
        )

        let f1 = FinancialGoal(
            name: "F1 Ticket",
            targetAmount: 450,
            currentSaved: 300,
            targetDate: targetDate,
            priority: .medium,
            plannedMonthlyContribution: 150,
            isProtected: true
        )

        let scenario = WhatIfScenario(type: .purchase, name: "New PC", amount: 1_500, intendedDate: nil)
        let result = engine.evaluate(scenario: scenario, summary: summary, goals: [miami, f1], calendar: calendar)

        #expect(result.status == .tradeOff)
        #expect(result.remainingAfterPurchase == -250)

        let miamiImpact = result.goalImpacts.first { $0.goalName == "Miami Trip" }
        #expect(miamiImpact?.impactLevel == .delayed)
        #expect(miamiImpact?.amountPulledFromGoal == 250)
        #expect((miamiImpact?.delayDays ?? 0) >= 55)

        let f1Impact = result.goalImpacts.first { $0.goalName == "F1 Ticket" }
        #expect(f1Impact?.impactLevel == .unaffected)
        #expect(f1Impact?.amountPulledFromGoal == 0)
    }

    @Test func marksPurchaseWaitWhenSafeCashAndGoalsAreInsufficient() throws {
        let summary = FinancialSummary(
            currentCash: 8_000,
            protectedCash: 7_000,
            safeToSpendThroughNovember: 1_250,
            safeToSpendThisWeek: 100
        )

        let smallGoal = FinancialGoal(
            name: "Trip",
            targetAmount: 200,
            currentSaved: 100,
            targetDate: Date(),
            plannedMonthlyContribution: 50
        )

        let scenario = WhatIfScenario(type: .purchase, name: "Laptop", amount: 2_000, intendedDate: nil)
        let result = engine.evaluate(scenario: scenario, summary: summary, goals: [smallGoal])

        #expect(result.status == .wait)
        #expect(result.remainingAfterPurchase == -750)
        #expect(result.recommendedDate != nil)
    }

    @Test func rejectsQuestionWithoutAmount() {
        #expect(throws: WhatIfEngine.EngineError.missingAmount) {
            try engine.parse(question: "Can I buy F1 tickets next month?")
        }
    }
}
