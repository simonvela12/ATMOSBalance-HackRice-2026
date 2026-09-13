import XCTest
@testable import FinancialCore

final class PlanningModelTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testVariableCashFlowsUseFinanciallyConservativeBounds() throws {
        let asOf = date(2026, 9, 12)
        let target = date(2026, 10, 1)
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOf,
            incomeEvents: [IncomeEvent(amount: 500, date: target, source: "Variable work", type: .oneTime, amountRange: AmountRange(minimum: 300, expected: 500, maximum: 800))],
            expenseEvents: [ExpenseEvent(amount: 200, date: target, category: "Utilities", amountRange: AmountRange(minimum: 150, expected: 200, maximum: 275))],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let conservative = try FinancialScenarioEngine.forecast(profile: profile, targetDate: target, scenario: .conservative, calendar: calendar)
        let expected = try FinancialScenarioEngine.forecast(profile: profile, targetDate: target, scenario: .expected, calendar: calendar)
        let optimistic = try FinancialScenarioEngine.forecast(profile: profile, targetDate: target, scenario: .optimistic, calendar: calendar)
        XCTAssertEqual(conservative.forecast.projectedCash, 1_025, accuracy: 0.001)
        XCTAssertEqual(expected.forecast.projectedCash, 1_300, accuracy: 0.001)
        XCTAssertEqual(optimistic.forecast.projectedCash, 1_650, accuracy: 0.001)
    }

    func testMonthlyRecurrencePreservesCalendarAnchor() {
        let first = date(2026, 1, 31)
        let rule = RecurrenceRule(cadence: .monthly, firstOccurrence: first)
        let dates = rule.occurrenceDates(through: date(2026, 4, 30), calendar: calendar)
        XCTAssertEqual(dates.count, 4)
        XCTAssertEqual(calendar.component(.month, from: dates[1]), 2)
        XCTAssertEqual(calendar.component(.day, from: dates[1]), 28)
    }

    func testMaterialityRequiresReviewWhenRiskChanges() {
        XCTAssertEqual(MaterialityPolicy.recurringAmountDecision(expectedAmount: 100, actualAmount: 100.50, sameMerchant: true, riskBefore: .normal, riskAfter: .belowRecommendedBuffer), .askUser)
    }
}
