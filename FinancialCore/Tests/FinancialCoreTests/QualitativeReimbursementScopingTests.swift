import XCTest
@testable import FinancialCore

final class QualitativeReimbursementScopingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testReimbursementPreservesDifferentAmountWithSameSourceAndDate() {
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let expenseDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let repaymentDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let horizon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30))!

        let existingReimbursement = IncomeEvent(
            amount: 40,
            date: repaymentDate,
            source: "Reimbursement: Dinner",
            type: .oneTime,
            confidence: 1
        )
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOf,
            incomeEvents: [existingReimbursement],
            expenseEvents: [
                ExpenseEvent(
                    amount: 85,
                    date: expenseDate,
                    category: "Dinner",
                    essential: false,
                    committed: true
                )
            ]
        )
        let result = QualitativeParseResult(
            originalText: "They owe me and will pay me back Friday.",
            directives: [.expectReimbursement(on: repaymentDate)],
            missingFields: [],
            matchedRules: ["expense-reimbursement"]
        )
        let context = QualitativeNoteContext(
            subject: .expense,
            referenceAmount: 85,
            referenceDate: expenseDate,
            label: "Dinner"
        )

        let first = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        XCTAssertTrue(first.didChange)
        XCTAssertEqual(first.profile.incomeEvents.count, 2)
        XCTAssertEqual(
            first.profile.incomeEvents.map(\.amount).sorted(),
            [40, 85]
        )

        let second = QualitativeProfileUpdater.apply(
            result,
            to: first.profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        XCTAssertFalse(second.didChange)
        XCTAssertEqual(second.profile.incomeEvents.count, 2)
        XCTAssertEqual(
            second.profile.incomeEvents.map(\.amount).sorted(),
            [40, 85]
        )
    }
}
