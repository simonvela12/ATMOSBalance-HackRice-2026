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
}
