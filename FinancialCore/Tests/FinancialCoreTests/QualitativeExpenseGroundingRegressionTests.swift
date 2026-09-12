import XCTest
@testable import FinancialCore

final class QualitativeExpenseGroundingRegressionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testRecurringExpenseRequiresExactSelectedTransaction() {
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let existingDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let missingReferenceDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let horizon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30))!

        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOf,
            expenseEvents: [
                ExpenseEvent(
                    amount: 25,
                    date: existingDate,
                    category: "Streaming",
                    essential: false,
                    committed: true
                )
            ]
        )

        let result = QualitativeParseResult(
            originalText: "This repeats monthly.",
            directives: [.setRecurrence(cadence: .monthly, firstDate: nil)],
            missingFields: [],
            matchedRules: ["expense-recurrence"]
        )

        let context = QualitativeNoteContext(
            subject: .expense,
            referenceAmount: 25,
            referenceDate: missingReferenceDate,
            label: "Streaming"
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        XCTAssertFalse(application.didChange)
        XCTAssertEqual(application.profile.expenseEvents.count, 1)
        XCTAssertEqual(application.profile.expenseEvents[0].date, existingDate)
    }
}
