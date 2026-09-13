import XCTest
@testable import FinancialCore

final class QualitativeIncomeGroundingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var asOfDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
    }

    private var horizon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
    }

    func testRecurringIncomeDoesNotAppearWithoutReferencedIncome() {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let profile = FinancialProfile(currentCash: 1_000, asOfDate: asOfDate)
        let result = QualitativeParseResult(
            originalText: "I get this every two weeks.",
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
            referenceDate: referenceDate,
            label: "Campus job"
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

    func testStaleReferencedIncomeDoesNotReclassifyMatchingFutureDeposits() {
        let staleReferenceDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let futureDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let futureDeposit = IncomeEvent(
            amount: 650,
            date: futureDate,
            source: "Campus job",
            type: .oneTime,
            confidence: 1
        )
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOfDate,
            incomeEvents: [futureDeposit]
        )
        let result = QualitativeParseResult(
            originalText: "This is recurring and I am only about 70% sure it arrives.",
            directives: [
                .setIncomeType(.recurring),
                .setIrregularIncomeConfidence(0.7)
            ],
            missingFields: [],
            matchedRules: ["income-recurring", "income-confidence"]
        )
        let context = QualitativeNoteContext(
            subject: .income,
            referenceAmount: 650,
            referenceDate: staleReferenceDate,
            label: "Campus job"
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        XCTAssertFalse(application.didChange)
        XCTAssertEqual(application.profile.incomeEvents.count, 1)
        XCTAssertEqual(application.profile.incomeEvents[0].id, futureDeposit.id)
        XCTAssertEqual(application.profile.incomeEvents[0].type, .oneTime)
        XCTAssertEqual(application.profile.incomeEvents[0].confidence, 1, accuracy: 0.000_001)
    }

    func testRecurringIncomeUsesReferencedBankTransactionAsAnchor() {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!
        let existing = IncomeEvent(
            amount: 650,
            date: referenceDate,
            source: "Campus job",
            type: .oneTime,
            confidence: 1
        )
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: asOfDate,
            incomeEvents: [existing]
        )
        let result = QualitativeParseResult(
            originalText: "I get this every two weeks.",
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
            referenceDate: referenceDate,
            label: "Campus job"
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        XCTAssertTrue(application.didChange)
        XCTAssertTrue(application.profile.incomeEvents.contains {
            $0.date == referenceDate && $0.source == "Campus job" && $0.type == .recurring
        })
        XCTAssertTrue(application.profile.incomeEvents.contains {
            $0.date == calendar.date(from: DateComponents(year: 2026, month: 9, day: 20)) &&
            $0.amount == 650 && $0.source == "Campus job"
        })
    }
}

