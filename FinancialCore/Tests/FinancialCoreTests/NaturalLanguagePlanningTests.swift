import XCTest
@testable import FinancialCore

final class NaturalLanguagePlanningTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
    }

    func testSpanishFamilyIncomeExtractsAmountDateAndConfidence() {
        let draft = NaturalLanguagePlanningInterpreter.parse(
            "Mi familia me va a mandar $2,000 el 15 de octubre, probablemente 70%.",
            asOfDate: asOf,
            calendar: calendar
        )
        XCTAssertEqual(draft.kind, .income)
        XCTAssertEqual(draft.amount, 2_000)
        XCTAssertEqual(draft.confidence, 0.7, accuracy: 0.0001)
        XCTAssertEqual(draft.title, "Family support")
        XCTAssertEqual(draft.date, calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        XCTAssertTrue(draft.missingFields.isEmpty)
    }

    func testMonthlyRentExpenseIsCommittedAndRecurring() {
        let draft = NaturalLanguagePlanningInterpreter.parse(
            "Tengo que pagar $900 de renta el 1 de octubre cada mes.",
            asOfDate: asOf,
            calendar: calendar
        )
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertEqual(draft.amount, 900)
        XCTAssertEqual(draft.title, "Rent")
        XCTAssertEqual(draft.cadence, .monthly)
        XCTAssertTrue(draft.committed)
        XCTAssertTrue(draft.essential)
        XCTAssertEqual(draft.date, calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
    }

    func testGoalExtractsPurposeAndISODate() {
        let draft = NaturalLanguagePlanningInterpreter.parse(
            "Quiero ahorrar $900 para Miami para 2026-11-01.",
            asOfDate: asOf,
            calendar: calendar
        )
        XCTAssertEqual(draft.kind, .goal)
        XCTAssertEqual(draft.amount, 900)
        XCTAssertEqual(draft.date, calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        XCTAssertEqual(draft.goalPriority, .flexible)
        XCTAssertTrue(draft.title.lowercased().contains("miami"))
    }

    func testReserveDoesNotRequireFutureDate() {
        let draft = NaturalLanguagePlanningInterpreter.parse(
            "Quiero mantener al menos $500 sin tocar.",
            asOfDate: asOf,
            calendar: calendar
        )
        XCTAssertEqual(draft.kind, .reserve)
        XCTAssertEqual(draft.amount, 500)
        XCTAssertEqual(draft.date, asOf)
        XCTAssertTrue(draft.missingFields.isEmpty)
    }

    func testMissingDateIsRequestedInsteadOfGuessed() {
        let draft = NaturalLanguagePlanningInterpreter.parse(
            "Me van a pagar $800 por tutoring.",
            asOfDate: asOf,
            calendar: calendar
        )
        XCTAssertEqual(draft.kind, .income)
        XCTAssertEqual(draft.amount, 800)
        XCTAssertNil(draft.date)
        XCTAssertTrue(draft.missingFields.contains(.date))
    }

    func testOptionalExpenseIsNotCommitted() {
        let draft = NaturalLanguagePlanningInterpreter.parse(
            "Voy a pagar $60 por una suscripcion el 20 de septiembre pero puedo cancelar.",
            asOfDate: asOf,
            calendar: calendar
        )
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertFalse(draft.committed)
        XCTAssertFalse(draft.essential)
    }
}
