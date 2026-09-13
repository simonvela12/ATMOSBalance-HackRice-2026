import XCTest
@testable import FinancialCore

final class FinancialInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testTimelineProducesSafeTightAndNotSafeHealthStates() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 350,
                    date: date(2026, 9, 10),
                    category: "Known bill"
                ),
                ExpenseEvent(
                    amount: 200,
                    date: date(2026, 9, 15),
                    category: "Second bill"
                )
            ],
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 6,
                bufferWeeks: 0,
                manualMinimumBuffer: 200
            )
        )

        let timeline = try FinancialInsights.cashFlowTimeline(
            profile: profile,
            from: asOf,
            through: date(2026, 9, 16),
            calendar: calendar
        )

        let byDate = Dictionary(uniqueKeysWithValues: timeline.map { ($0.date, $0) })

        XCTAssertEqual(byDate[asOf]?.status, .safe)
        XCTAssertEqual(byDate[date(2026, 9, 10)]?.status, .tight)
        XCTAssertEqual(byDate[date(2026, 9, 15)]?.status, .notSafe)
        XCTAssertEqual(byDate[date(2026, 9, 15)]?.projectedCash ?? 0, 450, accuracy: 0.001)
        XCTAssertEqual(byDate[date(2026, 9, 15)]?.recommendedFloor ?? 0, 700, accuracy: 0.001)
    }

    func testWeeklyBudgetRecommendationSpreadsAdditionalCapacityAcrossWeeks() throws {
        let asOf = date(2026, 9, 1)
        let weeklyHistory = (0..<6).map { index in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                totalVariableSpending: 50
            )
        }
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            weeklySpendingHistory: weeklyHistory,
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 6,
                bufferWeeks: 0,
                manualMinimumBuffer: 100
            )
        )

        let result = try FinancialInsights.weeklyBudgetRecommendation(
            profile: profile,
            from: asOf,
            through: date(2026, 9, 15),
            calendar: calendar
        )

        // Baseline variable spending is already projected by FinancialEngine.
        // Over this inclusive 15-day window, three weekly allowance debits are possible.
        XCTAssertEqual(result.typicalWeeklySpending, 50, accuracy: 0.001)
        XCTAssertEqual(result.additionalWeeklyCapacity, 100, accuracy: 0.001)
        XCTAssertEqual(result.recommendedWeeklySpendingLimit, 150, accuracy: 0.001)
        XCTAssertEqual(result.limitingDate, date(2026, 9, 15))
    }

    func testDashboardPreservesPathSafeVsTargetDateDistinction() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 8000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 7000)
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
                    category: "Essential"
                )
            ],
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 6,
                bufferWeeks: 0,
                manualMinimumBuffer: 250
            )
        )

        let dashboard = try FinancialInsights.dashboard(
            profile: profile,
            through: date(2026, 11, 30),
            calendar: calendar
        )
        let target = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(2026, 11, 30),
            calendar: calendar
        )

        XCTAssertEqual(target.recommendedHeadroom, 1250, accuracy: 0.001)
        XCTAssertEqual(dashboard.safeToSpendNow, 750, accuracy: 0.001)
        XCTAssertEqual(dashboard.currentStatus, .safe)
        XCTAssertEqual(dashboard.minimumRecommendedHeadroom, 750, accuracy: 0.001)
        XCTAssertEqual(dashboard.tightestDate, asOf)
    }

    func testReserveIncreaseBecomesWeeklyBudgetLimitingDate() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 2000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500),
                PersonalReserveStep(effectiveDate: date(2026, 9, 15), minimumCash: 1400)
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        let result = try FinancialInsights.weeklyBudgetRecommendation(
            profile: profile,
            from: asOf,
            through: date(2026, 9, 15),
            calendar: calendar
        )

        XCTAssertEqual(result.additionalWeeklyCapacity, 200, accuracy: 0.001)
        XCTAssertEqual(result.limitingDate, date(2026, 9, 15))
    }
}

