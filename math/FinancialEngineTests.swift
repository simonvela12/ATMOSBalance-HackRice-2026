import XCTest
@testable import Hackathon2026

final class FinancialEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testReferenceScenarioSafeToSpendIs1250() throws {
        let profile = FinancialProfile(
            currentCash: 8000,
            protectedCash: 7000,
            safetyBuffer: 250,
            asOfDate: makeDate(2026, 9, 12),
            incomeEvents: [
                IncomeEvent(
                    amount: 1000,
                    date: makeDate(2026, 11, 1),
                    source: "Expected income",
                    type: .recurring
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 500,
                    date: makeDate(2026, 11, 15),
                    category: "Essential living expenses"
                )
            ],
            goals: []
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: makeDate(2026, 11, 30)
        )

        XCTAssertEqual(result.projectedBalance, 8500, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpend, 1250, accuracy: 0.001)
    }

    func testIrregularIncomeUsesConfidence() throws {
        let profile = FinancialProfile(
            currentCash: 1000,
            protectedCash: 0,
            safetyBuffer: 0,
            asOfDate: makeDate(2026, 9, 12),
            incomeEvents: [
                IncomeEvent(
                    amount: 1000,
                    date: makeDate(2026, 10, 1),
                    source: "Tutoring",
                    type: .irregular,
                    confidence: 0.6
                )
            ],
            expenseEvents: [],
            goals: []
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: makeDate(2026, 10, 2)
        )

        XCTAssertEqual(result.expectedIncome, 600, accuracy: 0.001)
    }

    func testPastOneTimeIncomeIsNotCountedAgain() throws {
        let profile = FinancialProfile(
            currentCash: 3000,
            protectedCash: 0,
            safetyBuffer: 0,
            asOfDate: makeDate(2026, 9, 12),
            incomeEvents: [
                IncomeEvent(
                    amount: 1500,
                    date: makeDate(2026, 8, 20),
                    source: "Family transfer",
                    type: .oneTime
                )
            ],
            expenseEvents: [],
            goals: []
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: makeDate(2026, 10, 1)
        )

        XCTAssertEqual(result.expectedIncome, 0, accuracy: 0.001)
    }

    func testProtectedGoalIsNotDoubleCounted() throws {
        let profile = FinancialProfile(
            currentCash: 8000,
            protectedCash: 7000,
            safetyBuffer: 0,
            asOfDate: makeDate(2026, 9, 12),
            incomeEvents: [],
            expenseEvents: [],
            goals: [
                Goal(
                    name: "Miami",
                    targetAmount: 900,
                    deadline: makeDate(2026, 12, 18),
                    priority: .mandatory,
                    alreadyProtected: true
                )
            ]
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: makeDate(2026, 12, 18)
        )

        XCTAssertEqual(result.mandatoryGoalReserve, 0, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpend, 1000, accuracy: 0.001)
    }

    func testUnsafePurchaseReturnsWait() throws {
        let profile = FinancialProfile(
            currentCash: 1000,
            protectedCash: 700,
            safetyBuffer: 100,
            asOfDate: makeDate(2026, 9, 12),
            incomeEvents: [],
            expenseEvents: [],
            goals: []
        )

        let assessment = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 250,
            purchaseDate: makeDate(2026, 9, 13),
            planningHorizon: makeDate(2026, 10, 1),
            calendar: calendar
        )

        XCTAssertEqual(assessment.status, .wait)
        XCTAssertEqual(assessment.shortfall, 50, accuracy: 0.001)
    }

    func testPurchaseChecksFutureBillsNotJustPurchaseDay() throws {
        let profile = FinancialProfile(
            currentCash: 1000,
            protectedCash: 0,
            safetyBuffer: 100,
            asOfDate: makeDate(2026, 9, 12),
            incomeEvents: [],
            expenseEvents: [
                ExpenseEvent(
                    amount: 700,
                    date: makeDate(2026, 9, 30),
                    category: "Future bill"
                )
            ],
            goals: []
        )

        let assessment = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 400,
            purchaseDate: makeDate(2026, 9, 15),
            planningHorizon: makeDate(2026, 10, 1),
            calendar: calendar
        )

        XCTAssertEqual(assessment.safeToSpendOnPurchaseDate, 900, accuracy: 0.001)
        XCTAssertEqual(assessment.minimumSafeToSpendThroughHorizon, 200, accuracy: 0.001)
        XCTAssertEqual(assessment.status, .wait)
        XCTAssertEqual(assessment.shortfall, 200, accuracy: 0.001)
    }

    func testUserExampleF1MustWaitWhenProtectedMoneyIncludesGoals() throws {
        // Example supplied during HackRice brainstorming.
        // Assumption for this test: the $8,800 protected amount ALREADY includes
        // the Miami and October goals, so those goals must not be subtracted twice.
        // As-of date is Sep 11, therefore the Sep 5 one-time friend repayment is past
        // and is assumed to already be reflected in currentCash if it was received.
        let profile = FinancialProfile(
            currentCash: 9500,
            protectedCash: 8800,
            safetyBuffer: 150,
            asOfDate: makeDate(2026, 9, 11),
            incomeEvents: [
                IncomeEvent(
                    amount: 200,
                    date: makeDate(2026, 9, 5),
                    source: "Friend repayment",
                    type: .oneTime,
                    confidence: 0.9
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 200,
                    date: makeDate(2026, 10, 1),
                    category: "Subscriptions"
                ),
                ExpenseEvent(
                    amount: 150,
                    date: makeDate(2026, 10, 15),
                    category: "Miscellaneous"
                )
            ],
            goals: [
                Goal(
                    name: "Miami",
                    targetAmount: 1000,
                    deadline: makeDate(2026, 11, 26),
                    priority: .mandatory,
                    alreadyProtected: true
                ),
                Goal(
                    name: "Other goal",
                    targetAmount: 600,
                    deadline: makeDate(2026, 10, 25),
                    priority: .mandatory,
                    alreadyProtected: true
                )
            ]
        )

        let yearEnd = makeDate(2026, 12, 31)
        let result = try FinancialEngine.forecast(profile: profile, targetDate: yearEnd)

        XCTAssertEqual(result.expectedIncome, 0, accuracy: 0.001)
        XCTAssertEqual(result.projectedBalance, 9150, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpend, 200, accuracy: 0.001)

        let assessment = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 450,
            purchaseDate: makeDate(2026, 9, 15),
            planningHorizon: yearEnd,
            calendar: calendar
        )

        XCTAssertEqual(assessment.safeToSpendOnPurchaseDate, 550, accuracy: 0.001)
        XCTAssertEqual(assessment.minimumSafeToSpendThroughHorizon, 200, accuracy: 0.001)
        XCTAssertEqual(assessment.status, .wait)
        XCTAssertEqual(assessment.shortfall, 250, accuracy: 0.001)
        XCTAssertNil(assessment.recommendedDate)
    }
}
