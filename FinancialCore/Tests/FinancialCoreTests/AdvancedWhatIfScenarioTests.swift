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

    func testRecurringExpenseIsMaterializedOnRealDatesInsteadOfCollapsed() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 5_000,
            asOfDate: asOf,
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )
        let scenario = WhatIfScenario(
            title: "Monthly subscription",
            changes: [
                WhatIfCashFlowChange(
                    direction: .expense,
                    amount: 100,
                    startDate: date(2026, 10, 1),
                    recurrence: WhatIfRecurrence(every: 1, unit: .month),
                    label: "Subscription"
                )
            ]
        )

        let result = try FinancialInsights.analyzeWhatIfScenario(
            profile: profile,
            scenario: scenario,
            planningHorizon: date(2026, 12, 31),
            calendar: calendar
        )

        XCTAssertEqual(result.movements.count, 3)
        XCTAssertEqual(result.movements.map(\.date), [
            date(2026, 10, 1),
            date(2026, 11, 1),
            date(2026, 12, 1)
        ])
        XCTAssertEqual(result.totalExpenses, 300, accuracy: 0.001)
        XCTAssertEqual(result.totalIncome, 0, accuracy: 0.001)
    }

    func testCompoundScenarioSupportsUpfrontAndRecurringCostsTogether() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 10_000,
            asOfDate: asOf,
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )
        let scenario = WhatIfScenario(
            title: "Buy a car",
            changes: [
                WhatIfCashFlowChange(
                    direction: .expense,
                    amount: 4_000,
                    startDate: asOf,
                    label: "Car down payment"
                ),
                WhatIfCashFlowChange(
                    direction: .expense,
                    amount: 300,
                    startDate: date(2026, 10, 1),
                    recurrence: WhatIfRecurrence(every: 1, unit: .month),
                    label: "Car payment"
                )
            ]
        )

        let applied = try FinancialInsights.applyWhatIfScenario(
            profile: profile,
            scenario: scenario,
            planningHorizon: date(2026, 12, 31),
            calendar: calendar
        )

        XCTAssertEqual(applied.profile.currentCash, 6_000, accuracy: 0.001)
        XCTAssertEqual(applied.movements.count, 4)
        XCTAssertEqual(applied.profile.expenseEvents.filter { $0.category == "Car payment" }.count, 3)
    }

    func testWhatIfUsesReserveGoalsSpendingHistoryAndUncertaintyProfiles() throws {
        let asOf = date(2026, 9, 12)
        let goal = Goal(
            name: "Tuition",
            targetAmount: 2_000,
            amountAlreadyPaid: 500,
            deadline: date(2026, 12, 15),
            priority: .mandatory,
            flexibility: .low
        )
        let history = (0..<6).map { week -> WeeklySpendingSample in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(7 * (week + 1)), to: asOf)!,
                totalVariableSpending: Double(300 + week * 50)
            )
        }
        let profile = FinancialProfile(
            currentCash: 8_000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 2_000, note: "Emergency reserve")
            ],
            incomeEvents: [
                IncomeEvent(
                    amount: 1_000,
                    date: date(2026, 10, 1),
                    source: "Expected freelance income",
                    type: .irregular,
                    confidence: 0.6
                )
            ],
            goals: [goal],
            weeklySpendingHistory: history,
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2, manualMinimumBuffer: 0)
        )
        let scenario = WhatIfScenario(
            title: "New monthly rent",
            changes: [
                WhatIfCashFlowChange(
                    direction: .expense,
                    amount: 700,
                    startDate: date(2026, 10, 1),
                    recurrence: WhatIfRecurrence(every: 1, unit: .month),
                    label: "Additional rent",
                    essential: true
                )
            ]
        )

        let result = try FinancialInsights.analyzeWhatIfScenario(
            profile: profile,
            scenario: scenario,
            planningHorizon: date(2026, 12, 31),
            calendar: calendar
        )

        XCTAssertEqual(result.scenarioOutcomes.count, FinancialScenario.allCases.count)
        XCTAssertEqual(Set(result.scenarioOutcomes.map(\.financialScenario)), Set(FinancialScenario.allCases))
        XCTAssertLessThan(result.projected.safeToSpendNow, result.baseline.safeToSpendNow)
        XCTAssertEqual(result.totalExpenses, 2_100, accuracy: 0.001)
        XCTAssertFalse(result.smartGoalImpacts.isEmpty)

        let conservative = try XCTUnwrap(result.scenarioOutcomes.first { $0.financialScenario == .conservative })
        let optimistic = try XCTUnwrap(result.scenarioOutcomes.first { $0.financialScenario == .optimistic })
        XCTAssertLessThanOrEqual(conservative.safeToSpendAfter, optimistic.safeToSpendAfter)
    }
}
