import XCTest
@testable import FinancialCore

final class QualitativeIncomeScopingTests: XCTestCase {
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

    func testIncomeConfidenceOnlyChangesMatchingAmountWithinSharedSource() {
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        let unrelatedDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let selected = IncomeEvent(
            amount: 450,
            date: selectedDate,
            source: "Campus job",
            type: .recurring,
            confidence: 1
        )
        let unrelated = IncomeEvent(
            amount: 1200,
            date: unrelatedDate,
            source: "Campus job",
            type: .oneTime,
            confidence: 1
        )
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOfDate,
            incomeEvents: [selected, unrelated]
        )
        let result = QualitativeParseResult(
            originalText: "This 450 payment is irregular and about 60% likely.",
            directives: [.setIncomeType(.irregular), .setIrregularIncomeConfidence(0.6)],
            missingFields: [],
            matchedRules: ["income-irregular", "income-confidence"]
        )
        let context = QualitativeNoteContext(
            subject: .income,
            referenceAmount: 450,
            referenceDate: selectedDate,
            label: "Campus job"
        )

        let application = QualitativeProfileUpdater.apply(
            result,
            to: profile,
            context: context,
            through: horizon,
            calendar: calendar
        )

        let selectedAfter = application.profile.incomeEvents.first { $0.id == selected.id }
        let unrelatedAfter = application.profile.incomeEvents.first { $0.id == unrelated.id }
        XCTAssertTrue(application.didChange)
        XCTAssertEqual(selectedAfter?.type, .irregular)
        XCTAssertEqual(selectedAfter?.confidence ?? -1, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(unrelatedAfter?.type, .oneTime)
        XCTAssertEqual(unrelatedAfter?.confidence ?? -1, 1, accuracy: 0.000_001)
    }

    func testOneTimeIncomeOnlyRemovesFutureEventsFromMatchingAmountSeries() {
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let matchingFutureDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let unrelatedFutureDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26))!
        let selected = IncomeEvent(
            amount: 450,
            date: selectedDate,
            source: "Campus job",
            type: .recurring,
            confidence: 1
        )
        let matchingFuture = IncomeEvent(
            amount: 450,
            date: matchingFutureDate,
            source: "Campus job",
            type: .recurring,
            confidence: 1
        )
        let unrelatedFuture = IncomeEvent(
            amount: 1200,
            date: unrelatedFutureDate,
            source: "Campus job",
            type: .oneTime,
            confidence: 1
        )
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOfDate,
            incomeEvents: [selected, matchingFuture, unrelatedFuture]
        )
        let result = QualitativeParseResult(
            originalText: "That 450 payment was one time.",
            directives: [.setIncomeType(.oneTime)],
            missingFields: [],
            matchedRules: ["income-one-time"]
        )
        let context = QualitativeNoteContext(
            subject: .income,
            referenceAmount: 450,
            referenceDate: selectedDate,
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
        XCTAssertNotNil(application.profile.incomeEvents.first { $0.id == selected.id })
        XCTAssertNil(application.profile.incomeEvents.first { $0.id == matchingFuture.id })
        XCTAssertNotNil(application.profile.incomeEvents.first { $0.id == unrelatedFuture.id })
        XCTAssertEqual(
            application.profile.incomeEvents.first { $0.id == unrelatedFuture.id }?.amount,
            1200
        )
    }
}

