import XCTest
@testable import FinancialCore

final class ContextV2PlanningTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testIncomeAndExpenseRangesResolveInOppositeDirections() {
        let range = AmountRange(minimum: 300, expected: 400, maximum: 500)
        XCTAssertEqual(range.amount(for: .conservative, direction: .income), 300)
        XCTAssertEqual(range.amount(for: .expected, direction: .income), 400)
        XCTAssertEqual(range.amount(for: .optimistic, direction: .income), 500)
        XCTAssertEqual(range.amount(for: .conservative, direction: .expense), 500)
        XCTAssertEqual(range.amount(for: .expected, direction: .expense), 400)
        XCTAssertEqual(range.amount(for: .optimistic, direction: .expense), 300)
    }

    func testIncomeAndExpenseDateWindowsResolveInOppositeDirections() {
        let window = DateWindow(
            earliest: date(2026, 10, 1),
            expected: date(2026, 10, 15),
            latest: date(2026, 10, 31)
        )
        XCTAssertEqual(window.date(for: .conservative, direction: .income), date(2026, 10, 31))
        XCTAssertEqual(window.date(for: .expected, direction: .income), date(2026, 10, 15))
        XCTAssertEqual(window.date(for: .optimistic, direction: .income), date(2026, 10, 1))
        XCTAssertEqual(window.date(for: .conservative, direction: .expense), date(2026, 10, 1))
        XCTAssertEqual(window.date(for: .optimistic, direction: .expense), date(2026, 10, 31))
    }

    func testRecurrenceEndDateIsInclusiveAndStopsLaterOccurrences() {
        let rule = RecurrenceRule(
            cadence: .monthly,
            firstOccurrence: date(2026, 9, 1),
            endDate: date(2026, 12, 1)
        )
        XCTAssertEqual(
            rule.occurrenceDates(through: date(2027, 3, 1), calendar: calendar),
            [date(2026, 9, 1), date(2026, 10, 1), date(2026, 11, 1), date(2026, 12, 1)]
        )
    }

    func testOpenRecurrenceStopsAtPlanningHorizon() {
        let rule = RecurrenceRule(cadence: .biweekly, firstOccurrence: date(2026, 9, 1))
        XCTAssertEqual(
            rule.occurrenceDates(through: date(2026, 9, 30), calendar: calendar),
            [date(2026, 9, 1), date(2026, 9, 15), date(2026, 9, 29)]
        )
    }

    func testPausedRecurrenceGeneratesNothing() {
        let rule = RecurrenceRule(cadence: .weekly, firstOccurrence: date(2026, 9, 1), isPaused: true)
        XCTAssertTrue(rule.occurrenceDates(through: date(2026, 12, 1), calendar: calendar).isEmpty)
    }

    func testScenarioEngineResolvesRangesAndWindowsButPreservesLegacyConfidence() {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            incomeEvents: [
                IncomeEvent(
                    amount: 550,
                    date: date(2026, 10, 15),
                    source: "Tutoring",
                    type: .irregular,
                    confidence: 0.7,
                    amountRange: AmountRange(minimum: 450, expected: 550, maximum: 650),
                    dateWindow: DateWindow(
                        earliest: date(2026, 10, 1),
                        expected: date(2026, 10, 15),
                        latest: date(2026, 10, 31)
                    )
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 400,
                    date: date(2026, 10, 15),
                    category: "Books",
                    amountRange: AmountRange(minimum: 300, expected: 400, maximum: 500),
                    dateWindow: DateWindow(
                        earliest: date(2026, 10, 1),
                        expected: date(2026, 10, 15),
                        latest: date(2026, 10, 31)
                    )
                )
            ]
        )

        let conservative = FinancialScenarioEngine.adjustedProfile(profile, for: .conservative, calendar: calendar)
        XCTAssertEqual(conservative.incomeEvents[0].amount, 450)
        XCTAssertEqual(conservative.incomeEvents[0].adjustedAmount, 0)
        XCTAssertEqual(conservative.incomeEvents[0].date, date(2026, 10, 31))
        XCTAssertEqual(conservative.expenseEvents[0].amount, 500)
        XCTAssertEqual(conservative.expenseEvents[0].date, date(2026, 10, 1))

        let expected = FinancialScenarioEngine.adjustedProfile(profile, for: .expected, calendar: calendar)
        XCTAssertEqual(expected.incomeEvents[0].amount, 550)
        XCTAssertEqual(expected.incomeEvents[0].adjustedAmount, 385, accuracy: 0.001)
        XCTAssertEqual(expected.expenseEvents[0].amount, 400)

        let optimistic = FinancialScenarioEngine.adjustedProfile(profile, for: .optimistic, calendar: calendar)
        XCTAssertEqual(optimistic.incomeEvents[0].amount, 650)
        XCTAssertEqual(optimistic.incomeEvents[0].adjustedAmount, 650)
        XCTAssertEqual(optimistic.incomeEvents[0].date, date(2026, 10, 1))
        XCTAssertEqual(optimistic.expenseEvents[0].amount, 300)
        XCTAssertEqual(optimistic.expenseEvents[0].date, date(2026, 10, 31))
    }

    func testLegacyEventsRemainUnchangedWithoutPlanningMetadata() {
        let asOf = date(2026, 9, 1)
        let income = IncomeEvent(amount: 200, date: date(2026, 9, 15), source: "One time", type: .oneTime)
        let expense = ExpenseEvent(amount: 80, date: date(2026, 9, 20), category: "Phone")
        let profile = FinancialProfile(currentCash: 1000, asOfDate: asOf, incomeEvents: [income], expenseEvents: [expense])
        let expected = FinancialScenarioEngine.adjustedProfile(profile, for: .expected, calendar: calendar)
        XCTAssertEqual(expected.incomeEvents[0].amount, 200)
        XCTAssertEqual(expected.incomeEvents[0].date, date(2026, 9, 15))
        XCTAssertEqual(expected.expenseEvents[0].amount, 80)
        XCTAssertEqual(expected.expenseEvents[0].date, date(2026, 9, 20))
    }

    func testTinySameMerchantChangeAutoAppliesUnlessRiskChanges() {
        XCTAssertEqual(
            MaterialityPolicy.recurringAmountDecision(
                expectedAmount: 20,
                actualAmount: 22,
                sameMerchant: true,
                riskBefore: .normal,
                riskAfter: .normal
            ),
            .autoApply
        )
        XCTAssertEqual(
            MaterialityPolicy.recurringAmountDecision(
                expectedAmount: 20,
                actualAmount: 22,
                sameMerchant: true,
                riskBefore: .normal,
                riskAfter: .belowHardFloor
            ),
            .askUser
        )
        XCTAssertEqual(
            MaterialityPolicy.recurringAmountDecision(
                expectedAmount: 20,
                actualAmount: 35,
                sameMerchant: true,
                riskBefore: .normal,
                riskAfter: .normal
            ),
            .askUser
         )
    }

    func testStrongPlannedMatchAutoLinksWithinAmountAndDateTolerance() {
        XCTAssertEqual(
            MaterialityPolicy.plannedMatchDecision(
                plannedAmount: 900,
                actualAmount: 905,
                plannedDate: date(2026, 10, 1),
                actualDate: date(2026, 10, 2),
                strongIdentity: true,
                riskBefore: .normal,
                riskAfter: .normal,
                calendar: calendar
            ),
            .autoApply
        )
        XCTAssertEqual(
            MaterialityPolicy.plannedMatchDecision(
                plannedAmount: 900,
                actualAmount: 950,
                plannedDate: date(2026, 10, 1),
                actualDate: date(2026, 10, 2),
                strongIdentity: true,
                riskBefore: .normal,
                riskAfter: .normal,
                calendar: calendar
            ),
            .askUser
        )
    }
}
