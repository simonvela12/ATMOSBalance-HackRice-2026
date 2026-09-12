import XCTest
@testable import FinancialCore

final class QualitativeProfileUpdaterTests: XCTestCase {
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

    func testIncompleteInterpretationDoesNotMutateProfile() {
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOfDate,
            expenseEvents: [
                ExpenseEvent(amount: 25, date: horizon, category: "Streaming", essential: false, committed: true)
            ]
        )
        let result = QualitativeParseResult(
            originalText: "recurring",
            directives: [.setExpenseCommitted(false)],
            missingFields: [.recurrenceCadence],
            matchedRules: ["expense-not-committed", "expense-recurring-missing-cadence"]
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: QualitativeNoteContext(subject: .expense, referenceAmount: 25, label: "Streaming"),
            through: horizon,
            calendar: calendar
        )

        XCTAssertFalse(application.didChange)
        XCTAssertEqual(application.profile.expenseEvents.first?.committed, true)
    }

    func testExistingExpenseStateReturnsNoChange() {
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOfDate,
            expenseEvents: [
                ExpenseEvent(amount: 25, date: horizon, category: "Streaming", essential: false, committed: false)
            ]
        )
        let result = QualitativeParseResult(
            originalText: "optional",
            directives: [.setExpenseCommitted(false), .setExpenseEssential(false)],
            missingFields: [],
            matchedRules: ["expense-not-committed", "expense-nonessential"]
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: QualitativeNoteContext(subject: .expense, referenceAmount: 25, label: "Streaming"),
            through: horizon,
            calendar: calendar
        )

        XCTAssertFalse(application.didChange)
        XCTAssertEqual(application.profile.expenseEvents.count, 1)
    }

    func testExpenseCommitmentChangeIsReportedAndApplied() {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOfDate,
            expenseEvents: [
                ExpenseEvent(amount: 25, date: eventDate, category: "Streaming", essential: false, committed: true)
            ]
        )
        let result = QualitativeParseResult(
            originalText: "optional",
            directives: [.setExpenseCommitted(false)],
            missingFields: [],
            matchedRules: ["expense-not-committed"]
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: QualitativeNoteContext(subject: .expense, referenceAmount: 25, label: "Streaming"),
            through: horizon,
            calendar: calendar
        )

        XCTAssertTrue(application.didChange)
        XCTAssertEqual(application.profile.expenseEvents.first?.committed, false)
    }

    func testIncomeTypeDirectiveActuallyChangesMatchingIncome() {
        let incomeDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOfDate,
            incomeEvents: [
                IncomeEvent(amount: 400, date: incomeDate, source: "Campus job", type: .recurring)
            ]
        )
        let result = QualitativeParseResult(
            originalText: "irregular",
            directives: [.setIncomeType(.irregular), .setIrregularIncomeConfidence(0.6)],
            missingFields: [],
            matchedRules: ["income-irregular", "income-confidence"]
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: QualitativeNoteContext(subject: .income, referenceAmount: 400, label: "Campus job"),
            through: horizon,
            calendar: calendar
        )

        XCTAssertTrue(application.didChange)
        XCTAssertEqual(application.profile.incomeEvents.first?.type, .irregular)
        XCTAssertEqual(application.profile.incomeEvents.first?.confidence, 0.6, accuracy: 0.000_001)
    }

    func testConfirmingSameRecurringInterpretationTwiceIsIdempotent() {
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
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
            referenceAmount: 650,
            referenceDate: anchor,
            label: "Campus job"
        )
        let profile = FinancialProfile(currentCash: 1000, asOfDate: asOfDate)

        let first = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: context,
            through: horizon,
            calendar: calendar
        )
        let second = QualitativeProfileUpdater.apply(
            result,
            to: first.profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        XCTAssertTrue(first.didChange)
        XCTAssertFalse(second.didChange)
        XCTAssertEqual(second.profile.incomeEvents.count, first.profile.incomeEvents.count)
        XCTAssertEqual(
            second.profile.incomeEvents.map(\.date).sorted(),
            first.profile.incomeEvents.map(\.date).sorted()
        )
    }

    func testIdenticalReimbursementDoesNotDuplicateOrReportChange() {
        let repaymentDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let existing = IncomeEvent(
            amount: 85,
            date: repaymentDate,
            source: "Reimbursement: Dinner",
            type: .oneTime,
            confidence: 1
        )
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOfDate,
            incomeEvents: [existing]
        )
        let result = QualitativeParseResult(
            originalText: "pay me back Friday",
            directives: [.expectReimbursement(on: repaymentDate)],
            missingFields: [],
            matchedRules: ["expense-reimbursement"]
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: QualitativeNoteContext(subject: .expense, referenceAmount: 85, label: "Dinner"),
            through: horizon,
            calendar: calendar
        )

        XCTAssertFalse(application.didChange)
        XCTAssertEqual(application.profile.incomeEvents.count, 1)
        XCTAssertEqual(application.profile.incomeEvents.first?.id, existing.id)
    }
}
