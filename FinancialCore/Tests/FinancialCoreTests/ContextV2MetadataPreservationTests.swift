import XCTest
@testable import FinancialCore

final class ContextV2MetadataPreservationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testIncomeContextEditPreservesV2PlanningMetadata() {
        let asOf = date(2026, 9, 12)
        let eventDate = date(2026, 10, 15)
        let range = AmountRange(minimum: 450, expected: 550, maximum: 650)
        let window = DateWindow(
            earliest: date(2026, 10, 1),
            expected: eventDate,
            latest: date(2026, 10, 31)
        )
        let recurrence = RecurrenceRule(
            cadence: PlanningRecurrenceCadence.monthly,
            firstOccurrence: eventDate,
            endDate: date(2026, 12, 15)
        )
        let allocation = IncomeAllocation(amount: 300, purpose: "Tuition")
        let original = IncomeEvent(
            amount: 550,
            date: eventDate,
            source: "Tutoring",
            type: .irregular,
            confidence: 0.4,
            amountRange: range,
            dateWindow: window,
            recurrenceRule: recurrence,
            allocations: [allocation],
            planningSource: .planned,
            planningStatus: .planned
        )
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOf,
            incomeEvents: [original]
        )
        let result = QualitativeParseResult(
            originalText: "likely 60 percent",
            directives: [.setIrregularIncomeConfidence(0.6)],
            missingFields: [],
            matchedRules: ["income-confidence"]
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: QualitativeNoteContext(
                subject: .income,
                referenceAmount: 550,
                referenceDate: eventDate,
                label: "Tutoring"
            ),
            through: date(2027, 1, 1),
            calendar: calendar
        )

        let updated = application.profile.incomeEvents[0]
        XCTAssertTrue(application.didChange)
        XCTAssertEqual(updated.confidence, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(updated.amountRange, range)
        XCTAssertEqual(updated.dateWindow, window)
        XCTAssertEqual(updated.recurrenceRule, recurrence)
        XCTAssertEqual(updated.allocations, [allocation])
        XCTAssertEqual(updated.planningSource, .planned)
        XCTAssertEqual(updated.planningStatus, .planned)
    }

    func testExpenseContextEditPreservesV2PlanningMetadata() {
        let asOf = date(2026, 9, 12)
        let eventDate = date(2026, 10, 1)
        let range = AmountRange(minimum: 18, expected: 20, maximum: 24)
        let window = DateWindow(
            earliest: date(2026, 9, 29),
            expected: eventDate,
            latest: date(2026, 10, 3)
        )
        let recurrence = RecurrenceRule(
            cadence: PlanningRecurrenceCadence.monthly,
            firstOccurrence: eventDate,
            endDate: date(2026, 12, 1)
        )
        let original = ExpenseEvent(
            amount: 20,
            date: eventDate,
            category: "Streaming",
            essential: false,
            committed: true,
            amountRange: range,
            dateWindow: window,
            recurrenceRule: recurrence,
            merchantIdentity: "netflix",
            planningSource: .planned,
            planningStatus: .planned
        )
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOf,
            expenseEvents: [original]
        )
        let result = QualitativeParseResult(
            originalText: "I can cancel this",
            directives: [.setExpenseCommitted(false)],
            missingFields: [],
            matchedRules: ["expense-not-committed"]
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: QualitativeNoteContext(
                subject: .expense,
                referenceAmount: 20,
                referenceDate: eventDate,
                label: "Streaming"
            ),
            through: date(2027, 1, 1),
            calendar: calendar
        )

        let updated = application.profile.expenseEvents[0]
        XCTAssertTrue(application.didChange)
        XCTAssertFalse(updated.committed)
        XCTAssertEqual(updated.amountRange, range)
        XCTAssertEqual(updated.dateWindow, window)
        XCTAssertEqual(updated.recurrenceRule, recurrence)
        XCTAssertEqual(updated.merchantIdentity, "netflix")
        XCTAssertEqual(updated.planningSource, .planned)
        XCTAssertEqual(updated.planningStatus, .planned)
    }
}
