import XCTest
@testable import FinancialCore

final class QualitativeGroundingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var asOfDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
    }

    private var horizon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 30))!
    }

    func testReimbursementDoesNotCreateIncomeWhenReferencedExpenseIsMissing() {
        let repaymentDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let profile = FinancialProfile(currentCash: 1_000, asOfDate: asOfDate)
        let result = QualitativeParseResult(
            originalText: "They owe me and will pay me back Friday.",
            directives: [.expectReimbursement(on: repaymentDate)],
            missingFields: [],
            matchedRules: ["expense-reimbursement"]
        )
        let context = QualitativeNoteContext(
            subject: .expense,
            referenceAmount: 85,
            referenceDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 10)),
            label: "Dinner"
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        XCTAssertFalse(application.didChange)
        XCTAssertTrue(application.profile.incomeEvents.isEmpty)
    }

    func testReimbursementCreatesIncomeWhenReferencedExpenseExists() {
        let expenseDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let repaymentDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOfDate,
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

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        XCTAssertTrue(application.didChange)
        XCTAssertEqual(application.profile.incomeEvents.count, 1)
        XCTAssertEqual(application.profile.incomeEvents.first?.amount, 85)
        XCTAssertEqual(application.profile.incomeEvents.first?.date, repaymentDate)
        XCTAssertEqual(application.profile.incomeEvents.first?.source, "Reimbursement: Dinner")
    }

    func testRecurringExpenseDoesNotAppearWithoutReferencedExpense() {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let profile = FinancialProfile(currentCash: 1_000, asOfDate: asOfDate)
        let result = QualitativeParseResult(
            originalText: "This is monthly.",
            directives: [.setRecurrence(cadence: .monthly, firstDate: nil)],
            missingFields: [],
            matchedRules: ["expense-recurrence"]
        )
        let context = QualitativeNoteContext(
            subject: .expense,
            referenceAmount: 20,
            referenceDate: referenceDate,
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
        XCTAssertTrue(application.profile.expenseEvents.isEmpty)
    }
}
