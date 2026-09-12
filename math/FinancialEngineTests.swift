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
            purchaseDate: makeDate(2026, 9, 13)
        )

        XCTAssertEqual(assessment.status, .wait)
        XCTAssertEqual(assessment.shortfall, 50, accuracy: 0.001)
    }
}
