import XCTest
@testable import FinancialCore

final class AdvancedWhatIfScenarioTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testRecurringExpenseUsesItsRealFutureDates() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(currentCash: 5_000, asOfDate: asOf, spendingPolicy: SpendingPolicy(bufferWeeks: 0))
        let scenario = WhatIfScenario(title: "Subscription", changes: [
            WhatIfCashFlowChange(
                direction: .expense,
                amount: 100,
                startDate: date(2026, 10, 1),
                recurrence: WhatIfRecurrence(unit: .month),
                label: "Subscription"
            )
        ])
        let result = try FinancialInsights.analyzeWhatIfScenario(
            profile: profile,
            scenario: scenario,
            planningHorizon: date(2026, 12, 31),
            calendar: calendar
        )
        XCTAssertEqual(result.movements.map(\.date), [date(2026, 10, 1), date(2026, 11, 1), date(2026, 12, 1)])
        XCTAssertEqual(result.totalExpenses, 300, accuracy: 0.001)
    }

    func testCompoundScenarioCombinesImmediateAndRecurringEvents() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(currentCash: 10_000, asOfDate: asOf, spendingPolicy: SpendingPolicy(bufferWeeks: 0))
        let scenario = WhatIfScenario(title: "Car", changes: [
            WhatIfCashFlowChange(direction: .expense, amount: 4_000, startDate: asOf, label: "Down payment"),
            WhatIfCashFlowChange(direction: .expense, amount: 300, startDate: date(2026, 10, 1), recurrence: WhatIfRecurrence(unit: .month), label: "Car payment")
        ])
        let applied = try FinancialInsights.applyWhatIfScenario(
            profile: profile,
            scenario: scenario,
            planningHorizon: date(2026, 12, 31),
            calendar: calendar
        )
        XCTAssertEqual(applied.profile.currentCash, 6_000, accuracy: 0.001)
        XCTAssertEqual(applied.movements.count, 4)
        XCTAssertEqual(applied.profile.expenseEvents.count, 3)
    }

    func testScenarioUsesFullProfileAndProducesThreeAssumptionOutcomes() throws {
        let asOf = date(2026, 9, 12)
        let goal = Goal(name: "Tuition", targetAmount: 2_000, amountAlreadyPaid: 500, deadline: date(2026, 12, 15), priority: .mandatory, flexibility: .low)
        let history = (1...6).map { week in
            WeeklySpendingSample(weekStart: calendar.date(byAdding: .weekOfYear, value: -week, to: asOf)!, totalVariableSpending: 350)
        }
        let profile = FinancialProfile(
            currentCash: 8_000,
            asOfDate: asOf,
            personalReserveSteps: [PersonalReserveStep(effectiveDate: asOf, minimumCash: 2_000)],
            incomeEvents: [IncomeEvent(amount: 1_000, date: date(2026, 10, 1), source: "Freelance", type: .irregular, confidence: 0.6)],
            goals: [goal],
            weeklySpendingHistory: history,
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2)
        )
        let scenario = WhatIfScenario(title: "Rent increase", changes: [
            WhatIfCashFlowChange(direction: .expense, amount: 700, startDate: date(2026, 10, 1), recurrence: WhatIfRecurrence(unit: .month), label: "Additional rent", essential: true)
        ])
        let result = try FinancialInsights.analyzeWhatIfScenario(profile: profile, scenario: scenario, planningHorizon: date(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(result.scenarioOutcomes.count, 3)
        XCTAssertLessThan(result.projected.minimumRecommendedHeadroom, result.baseline.minimumRecommendedHeadroom)
        XCTAssertFalse(result.smartGoalImpacts.isEmpty)
    }

    func testPurchaseCapacityProtectsImportantGoalAndCommittedRent() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 2_350,
            asOfDate: asOf,
            expenseEvents: [
                ExpenseEvent(amount: 200, date: date(2026, 10, 1), category: "Rent"),
                ExpenseEvent(amount: 200, date: date(2026, 11, 1), category: "Rent")
            ],
            goals: [
                Goal(
                    name: "Two-month objective",
                    targetAmount: 700,
                    deadline: date(2026, 11, 12),
                    priority: .medium
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )
        let scenario = WhatIfScenario(title: "Mac", changes: [
            WhatIfCashFlowChange(
                direction: .expense,
                amount: 1_300,
                startDate: asOf,
                label: "Mac"
            )
        ])

        let result = try FinancialInsights.analyzeWhatIfScenario(
            profile: profile,
            scenario: scenario,
            planningHorizon: date(2026, 11, 12),
            availableToSpendNow: 550,
            calendar: calendar
        )

        XCTAssertEqual(result.baseline.safeToSpendNow, 550, accuracy: 0.001)
        XCTAssertEqual(result.projected.safeToSpendNow, 0, accuracy: 0.001)
        XCTAssertFalse(result.worsenedSmartGoals.isEmpty)
        XCTAssertLessThan(result.safeToSpendChange, 0)
    }

    func testPurchaseProducesFiniteGoalDelayFromExpectedCashFlowDates() throws {
        let asOf = date(2026, 9, 12)
        let goal = Goal(
            name: "Trip",
            targetAmount: 700,
            deadline: date(2026, 11, 11),
            priority: .medium
        )
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOf,
            incomeEvents: [
                IncomeEvent(amount: 200, date: date(2026, 10, 27), source: "Pay 1", type: .oneTime),
                IncomeEvent(amount: 200, date: date(2026, 11, 3), source: "Pay 2", type: .oneTime)
            ],
            expenseEvents: [
                ExpenseEvent(amount: 400, date: date(2026, 10, 12), category: "Rent")
            ],
            goals: [goal],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )
        let scenario = WhatIfScenario(title: "Purchase", changes: [
            WhatIfCashFlowChange(direction: .expense, amount: 150, startDate: asOf, label: "Purchase")
        ])

        let result = try FinancialInsights.analyzeWhatIfScenario(
            profile: profile,
            scenario: scenario,
            planningHorizon: date(2027, 9, 12),
            availableToSpendNow: 500,
            calendar: calendar
        )
        let impact = try XCTUnwrap(result.smartGoalImpacts.first)

        XCTAssertEqual(impact.projectedCompletionDateBefore, date(2026, 10, 27))
        XCTAssertEqual(impact.projectedCompletionDateAfter, date(2026, 11, 3))
        XCTAssertEqual(impact.projectedCompletionDateChangeInDays, 7)
        XCTAssertTrue(impact.worsened)
    }
}
