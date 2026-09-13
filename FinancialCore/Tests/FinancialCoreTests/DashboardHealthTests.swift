import XCTest
@testable import FinancialCore

final class DashboardHealthTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testDashboardCanBeSafeTodayButNotSafeAcrossHorizon() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            expenseEvents: [
                ExpenseEvent(amount: 600, date: date(2026, 9, 20), category: "Upcoming bill")
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 100)
        )

        let dashboard = try FinancialInsights.dashboard(
            profile: profile,
            through: date(2026, 9, 30),
            calendar: calendar
        )

        XCTAssertEqual(dashboard.currentStatus, .safe)
        XCTAssertEqual(dashboard.horizonStatus, .notSafe)
        XCTAssertEqual(dashboard.safeToSpendNow, 0, accuracy: 0.001)
        XCTAssertEqual(dashboard.minimumHardHeadroom, -100, accuracy: 0.001)
        XCTAssertEqual(dashboard.tightestDate, date(2026, 9, 20))
    }
}

