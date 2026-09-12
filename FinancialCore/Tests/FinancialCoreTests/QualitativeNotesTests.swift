import XCTest
@testable import FinancialCore

final class QualitativeNotesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var asOfDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
    }

    func testSpanishNotFrequentIncomeBecomesIrregular() {
        let result = QualitativeNoteInterpreter.parse(
            "Esto no es frecuente.",
            context: QualitativeNoteContext(subject: .income),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setIncomeType(.irregular)))
        XCTAssertTrue(result.isActionable)
    }

    func testExplicitOneTimeIncomeBecomesOneTime() {
        let result = QualitativeNoteInterpreter.parse(
            "This is a one-time payment.",
            context: QualitativeNoteContext(subject: .income),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setIncomeType(.oneTime)))
        XCTAssertTrue(result.isActionable)
    }

    func testReimbursementTomorrowProducesDatedDirective() {
        let result = QualitativeNoteInterpreter.parse(
            "Me lo deben y me van a devolver mañana.",
            context: QualitativeNoteContext(subject: .expense, referenceAmount: 85),
            asOfDate: asOfDate,
            calendar: calendar
        )
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: asOfDate)!
        XCTAssertTrue(result.directives.contains(.expectReimbursement(on: tomorrow)))
        XCTAssertTrue(result.isActionable)
    }

    func testReimbursementWithoutDateRequestsRepaymentDate() {
        let result = QualitativeNoteInterpreter.parse(
            "They owe me for this and will pay me back.",
            context: QualitativeNoteContext(subject: .expense, referenceAmount: 120),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.recognizedSomething)
        XCTAssertTrue(result.missingFields.contains(.repaymentDate))
        XCTAssertFalse(result.isActionable)
    }

    func testBiweeklyIncomeCreatesRecurringClassificationAndCadence() {
        let result = QualitativeNoteInterpreter.parse(
            "I get this every two weeks.",
            context: QualitativeNoteContext(subject: .income),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setIncomeType(.recurring)))
        XCTAssertTrue(result.directives.contains(.setRecurrence(cadence: .biweekly, firstDate: nil)))
        XCTAssertTrue(result.isActionable)
    }

    func testGenericRecurringIncomeAsksForCadence() {
        let result = QualitativeNoteInterpreter.parse(
            "This is recurring income.",
            context: QualitativeNoteContext(subject: .income),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setIncomeType(.recurring)))
        XCTAssertTrue(result.missingFields.contains(.recurrenceCadence))
        XCTAssertFalse(result.isActionable)
    }

    func testOptionalExpenseIsNotCommitted() {
        let result = QualitativeNoteInterpreter.parse(
            "This is optional and I can cancel it.",
            context: QualitativeNoteContext(subject: .expense),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setExpenseCommitted(false)))
        XCTAssertTrue(result.isActionable)
    }

    func testMandatoryGoalClassification() {
        let result = QualitativeNoteInterpreter.parse(
            "I can't postpone this. It is mandatory.",
            context: QualitativeNoteContext(subject: .goal),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setGoalPriority(.mandatory)))
        XCTAssertTrue(result.isActionable)
    }

    func testFlexibleGoalClassification() {
        let result = QualitativeNoteInterpreter.parse(
            "This goal can wait.",
            context: QualitativeNoteContext(subject: .goal),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setGoalPriority(.flexible)))
        XCTAssertTrue(result.isActionable)
    }

    func testGeneralReserveExtractsAmount() {
        let result = QualitativeNoteInterpreter.parse(
            "I need to keep at least $500 untouched.",
            context: QualitativeNoteContext(subject: .general),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setPersonalReserve(amount: 500, effectiveDate: asOfDate)))
        XCTAssertTrue(result.isActionable)
    }

    func testReserveCanUseNamedFutureDate() {
        let result = QualitativeNoteInterpreter.parse(
            "I want a $1,000 reserve starting October 1.",
            context: QualitativeNoteContext(subject: .general),
            asOfDate: asOfDate,
            calendar: calendar
        )
        let expectedDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        XCTAssertTrue(result.directives.contains(.setPersonalReserve(amount: 1000, effectiveDate: expectedDate)))
        XCTAssertTrue(result.isActionable)
    }

    func testReserveWithoutCurrencyMarkerParsesAmountWhenAttachedToReservePhrase() {
        let result = QualitativeNoteInterpreter.parse(
            "I need to keep at least 500 untouched.",
            context: QualitativeNoteContext(subject: .general),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setPersonalReserve(amount: 500, effectiveDate: asOfDate)))
        XCTAssertTrue(result.isActionable)
    }

    func testReserveDateWithoutAmountRequestsAmountInsteadOfGuessingDayNumber() {
        let result = QualitativeNoteInterpreter.parse(
            "I want a reserve starting October 1.",
            context: QualitativeNoteContext(subject: .general),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.recognizedSomething)
        XCTAssertTrue(result.directives.isEmpty)
        XCTAssertEqual(result.missingFields, [.reserveAmount])
        XCTAssertFalse(result.isActionable)
    }

    func testReserveISODateWithoutAmountDoesNotTreatYearAsMoney() {
        let result = QualitativeNoteInterpreter.parse(
            "I need a reserve starting 2026-10-01.",
            context: QualitativeNoteContext(subject: .general),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.recognizedSomething)
        XCTAssertTrue(result.directives.isEmpty)
        XCTAssertEqual(result.missingFields, [.reserveAmount])
        XCTAssertFalse(result.isActionable)
    }

    func testIrregularIncomeConfidencePercentIsParsed() {
        let result = QualitativeNoteInterpreter.parse(
            "This is irregular and there is about a 60% chance I receive it.",
            context: QualitativeNoteContext(subject: .income),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertTrue(result.directives.contains(.setIncomeType(.irregular)))
        XCTAssertTrue(result.directives.contains(.setIrregularIncomeConfidence(0.6)))
        XCTAssertTrue(result.isActionable)
    }

    func testSpanishAbsoluteReimbursementDateIsParsed() {
        let result = QualitativeNoteInterpreter.parse(
            "Me deben esto y me pagan el 20 de septiembre de 2026.",
            context: QualitativeNoteContext(subject: .expense),
            asOfDate: asOfDate,
            calendar: calendar
        )
        let expectedDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20))!
        XCTAssertTrue(result.directives.contains(.expectReimbursement(on: expectedDate)))
        XCTAssertTrue(result.isActionable)
    }

    func testUnknownSentenceDoesNotGuess() {
        let result = QualitativeNoteInterpreter.parse(
            "I had a weird day and this transaction feels unusual.",
            context: QualitativeNoteContext(subject: .expense),
            asOfDate: asOfDate,
            calendar: calendar
        )
        XCTAssertFalse(result.recognizedSomething)
        XCTAssertFalse(result.isActionable)
        XCTAssertTrue(result.directives.isEmpty)
    }
}
