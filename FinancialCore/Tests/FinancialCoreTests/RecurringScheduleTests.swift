import XCTest
@testable import FinancialCore

final class RecurringScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testBiweeklyIncomeMaterializesExpectedOccurrences() throws {
        let events = try FinancialScheduleBuilder.recurringIncome(
            amount: 400,
            firstDate: date(2026, 9, 4),
            through: date(2026, 10, 2),
            source: "Campus job",
            cadence: .biweekly,
            calendar: calendar
        )

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.date), [
            date(2026, 9, 4),
            date(2026, 9, 18),
            date(2026, 10, 2)
        ])
        XCTAssertTrue(events.allSatisfy { $0.type == .recurring })
        XCTAssertTrue(events.allSatisfy { $0.amount == 400 })
    }

    func testMonthlyExpenseMaterializesThroughInclusiveHorizon() throws {
        let events = try FinancialScheduleBuilder.recurringExpense(
            amount: 25,
            firstDate: date(2026, 9, 15),
            through: date(2026, 12, 15),
            category: "Subscription",
            cadence: .monthly,
            essential: false,
            committed: true,
            calendar: calendar
        )

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map(\.date), [
            date(2026, 9, 15),
            date(2026, 10, 15),
            date(2026, 11, 15),
            date(2026, 12, 15)
        ])
        XCTAssertTrue(events.allSatisfy { $0.committed })
        XCTAssertTrue(events.allSatisfy { !$0.essential })
    }

    func testMonthlyScheduleDoesNotDriftAfterShortMonth() throws {
        let dates = try FinancialScheduleBuilder.dates(
            startingOn: date(2026, 1, 31),
            through: date(2026, 5, 31),
            cadence: .monthly,
            calendar: calendar
        )

        XCTAssertEqual(dates, [
            date(2026, 1, 31),
            date(2026, 2, 28),
            date(2026, 3, 31),
            date(2026, 4, 30),
            date(2026, 5, 31)
        ])
    }

    func testRecurringScheduleRejectsNegativeAmounts() {
        XCTAssertThrowsError(
            try FinancialScheduleBuilder.recurringExpense(
                amount: -10,
                firstDate: date(2026, 9, 1),
                through: date(2026, 10, 1),
                category: "Bad input",
                cadence: .monthly,
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(error as? FinancialEngineError, .negativeAmount)
        }
    }

    func testRecurringScheduleRejectsBackwardHorizon() {
        XCTAssertThrowsError(
            try FinancialScheduleBuilder.dates(
                startingOn: date(2026, 10, 1),
                through: date(2026, 9, 1),
                cadence: .monthly,
                calendar: calendar
            )
        ) { error in
            XCTAssertEqual(error as? FinancialEngineError, .invalidDateRange)
        }
    }
}
