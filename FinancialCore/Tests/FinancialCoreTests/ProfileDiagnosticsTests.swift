import XCTest
@testable import FinancialCore

final class ProfileDiagnosticsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testCleanProfileIsReadyForForecast() {
        let asOf = date(2026, 9, 1)
        let spending = (0..<3).map { index in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                totalVariableSpending: 80
            )
        }
        let profile = FinancialProfile(
            currentCash: 1500,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            weeklySpendingHistory: spending
        )

        let report = FinancialProfileDiagnostics.report(
            profile: profile,
            planningHorizon: date(2026, 11, 1),
            calendar: calendar
        )

        XCTAssertTrue(report.isReadyForForecast)
        XCTAssertFalse(report.hasErrors)
        XCTAssertFalse(report.issues.contains { $0.code == .noRecentSpendingHistory })
        XCTAssertEqual(report.recentSpendingSampleCount, 3)
    }

    func testLongHorizonAndMissingHistoryProduceWarningsNotErrors() {
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: date(2026, 9, 1)
        )

        let report = FinancialProfileDiagnostics.report(
            profile: profile,
            planningHorizon: date(2027, 9, 1),
            operationalHorizonDays: 180,
            calendar: calendar
        )

        XCTAssertTrue(report.isReadyForForecast)
        XCTAssertTrue(report.hasWarnings)
        XCTAssertTrue(report.issues.contains { $0.code == .longPlanningHorizon })
        XCTAssertTrue(report.issues.contains { $0.code == .noRecentSpendingHistory })
    }

    func testMalformedNegativeCashFlowInputsAreErrors() {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            incomeEvents: [
                IncomeEvent(
                    amount: -100,
                    date: date(2026, 9, 15),
                    source: "Bad income",
                    type: .oneTime
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: -50,
                    date: date(2026, 9, 10),
                    category: "Bad expense"
                )
            ],
            weeklySpendingHistory: [
                WeeklySpendingSample(
                    weekStart: asOf,
                    totalVariableSpending: -20
                )
            ]
        )

        let report = FinancialProfileDiagnostics.report(
            profile: profile,
            planningHorizon: date(2026, 10, 1),
            calendar: calendar
        )

        XCTAssertFalse(report.isReadyForForecast)
        XCTAssertTrue(report.issues.contains { $0.code == .negativeIncomeAmount })
        XCTAssertTrue(report.issues.contains { $0.code == .negativeExpenseAmount })
        XCTAssertTrue(report.issues.contains { $0.code == .negativeWeeklySpending })
    }

    func testOutOfRangeIrregularIncomeConfidenceIsSurfaced() {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            incomeEvents: [
                IncomeEvent(
                    amount: 500,
                    date: date(2026, 9, 20),
                    source: "Family transfer",
                    type: .irregular,
                    confidence: 1.4
                )
            ],
            spendingPolicy: SpendingPolicy(lookbackWeeks: 0)
        )

        let report = FinancialProfileDiagnostics.report(
            profile: profile,
            planningHorizon: date(2026, 10, 1),
            calendar: calendar
        )

        XCTAssertTrue(report.isReadyForForecast)
        XCTAssertTrue(report.issues.contains { $0.code == .irregularIncomeConfidenceClamped })
    }

    func testOverdueMandatoryGoalIsVisibleAsWarning() {
        let asOf = date(2026, 9, 10)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            goals: [
                Goal(
                    name: "Tuition",
                    targetAmount: 600,
                    deadline: date(2026, 9, 1),
                    priority: .mandatory
                )
            ],
            spendingPolicy: SpendingPolicy(lookbackWeeks: 0)
        )

        let report = FinancialProfileDiagnostics.report(
            profile: profile,
            planningHorizon: date(2026, 10, 1),
            calendar: calendar
        )

        XCTAssertTrue(report.isReadyForForecast)
        XCTAssertTrue(report.issues.contains {
            $0.code == .overdueMandatoryGoal && $0.severity == .warning
        })
    }
}

