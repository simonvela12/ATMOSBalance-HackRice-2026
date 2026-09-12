import XCTest
@testable import FinancialCore

final class QualitativeMaterializerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var asOfDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
    }

    func testReimbursementDirectiveCreatesOneTimeIncome() {
        let repaymentDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let result = QualitativeParseResult(
            originalText: "pay me back",
            directives: [.expectReimbursement(on: repaymentDate)],
            missingFields: [],
            matchedRules: ["expense-reimbursement"]
        )
        let context = QualitativeNoteContext(
            subject: .expense,
            referenceAmount: 85,
            referenceDate: asOfDate,
            label: "Dinner"
        )

        let income = QualitativeDirectiveMaterializer.reimbursementIncome(
            from: result,
            context: context
        )

        XCTAssertEqual(income?.amount, 85)
        XCTAssertEqual(income?.date, repaymentDate)
        XCTAssertEqual(income?.type, .oneTime)
        XCTAssertEqual(income?.confidence, 1)
    }

    func testRecurringIncomeUsesPastTransactionAsScheduleAnchor() throws {
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        let horizon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let result = QualitativeParseResult(
            originalText: "every two weeks",
            directives: [
                .setIncomeType(.recurring),
                .setRecurrence(cadence: .biweekly, firstDate: nil)
            ],
            missingFields: [],
            matchedRules: ["income-recurring", "income-recurrence"]
        )
        let context = QualitativeNoteContext(
            subject: .income,
            referenceAmount: 450,
            referenceDate: anchor,
            label: "Campus job"
        )

        let events = try QualitativeDirectiveMaterializer.recurringIncomeEvents(
            from: result,
            context: context,
            asOfDate: asOfDate,
            through: horizon,
            calendar: calendar
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].date, calendar.date(from: DateComponents(year: 2026, month: 9, day: 26)))
        XCTAssertEqual(events[1].date, calendar.date(from: DateComponents(year: 2026, month: 10, day: 10)))
        XCTAssertTrue(events.allSatisfy { $0.amount == 450 && $0.type == .recurring })
    }

    func testRecurringExpenseUsesQualitativeCommitmentFlags() throws {
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let horizon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30))!
        let result = QualitativeParseResult(
            originalText: "monthly but optional",
            directives: [
                .setRecurrence(cadence: .monthly, firstDate: nil),
                .setExpenseCommitted(false),
                .setExpenseEssential(false)
            ],
            missingFields: [],
            matchedRules: ["expense-recurrence", "expense-not-committed"]
        )
        let context = QualitativeNoteContext(
            subject: .expense,
            referenceAmount: 20,
            referenceDate: anchor,
            label: "Subscription"
        )

        let events = try QualitativeDirectiveMaterializer.recurringExpenseEvents(
            from: result,
            context: context,
            asOfDate: asOfDate,
            through: horizon,
            calendar: calendar
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { !$0.committed && !$0.essential })
    }

    func testReserveDirectiveBecomesReserveStep() {
        let result = QualitativeParseResult(
            originalText: "keep 500",
            directives: [.setPersonalReserve(amount: 500, effectiveDate: asOfDate)],
            missingFields: [],
            matchedRules: ["personal-reserve"]
        )

        let steps = QualitativeDirectiveMaterializer.reserveSteps(from: result)

        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].minimumCash, 500)
        XCTAssertEqual(steps[0].effectiveDate, asOfDate)
    }
}
