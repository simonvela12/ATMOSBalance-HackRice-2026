import XCTest
@testable import FinancialCore

final class HistoricalTransactionBoundaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    func testHistoricalLinkedTransactionsRemainContextOnlyAndDoNotDoubleCountCurrentCash() throws {
        let asOf = date(12)
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOf,
            incomeEvents: [
                IncomeEvent(
                    amount: 5_000,
                    date: date(10),
                    source: "Campus job",
                    type: .oneTime,
                    confidence: 1
                ),
                IncomeEvent(
                    amount: 600,
                    date: asOf,
                    source: "Same-day deposit",
                    type: .oneTime,
                    confidence: 1
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 4_000,
                    date: date(11),
                    category: "Past purchase",
                    essential: false,
                    committed: true
                ),
                ExpenseEvent(
                    amount: 300,
                    date: asOf,
                    category: "Same-day purchase",
                    essential: true,
                    committed: true
                )
            ]
        )

        let forecast = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(20),
            calendar: calendar
        )

        XCTAssertEqual(forecast.expectedIncome, 0, accuracy: 0.000_001)
        XCTAssertEqual(forecast.committedExpenses, 0, accuracy: 0.000_001)
        XCTAssertEqual(forecast.projectedCash, 1_000, accuracy: 0.000_001)

        // Historical bank records intentionally remain in the profile so Context can ground
        // qualitative notes against real transactions without replaying them into today's cash.
        XCTAssertEqual(profile.incomeEvents.count, 2)
        XCTAssertEqual(profile.expenseEvents.count, 2)
    }
}

