import XCTest
@testable import Hackathon2026

final class FinancialScenarioEngineV2Tests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeProfile(
        currentCash: Double = 1000,
        asOfDate: Date,
        reserveSteps: [PersonalReserveStep] = [],
        incomeEvents: [V2IncomeEvent] = [],
        weeklySpendingHistory: [WeeklySpendingSample] = [],
        safetyBufferPolicy: SafetyBufferPolicy = SafetyBufferPolicy(weeksOfCoverage: 0)
    ) -> FinancialProfileV2 {
        FinancialProfileV2(
            currentCash: currentCash,
            asOfDate: asOfDate,
            personalReserveSteps: reserveSteps,
            institutionalMinimums: [],
            incomeEvents: incomeEvents,
            expenseEvents: [],
            goals: [],
            weeklySpendingHistory: weeklySpendingHistory,
            safetyBufferPolicy: safetyBufferPolicy
        )
    }

    func testScenarioSpendingUsesHistoryBasedQuartiles() {
        let asOf = makeDate(2026, 9, 1)
        let amounts: [Double] = [80, 95, 87, 92, 410, 90]
        let samples = amounts.enumerated().map { index, amount in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                totalVariableSpending: amount
            )
        }

        let profile = makeProfile(
            asOfDate: asOf,
            weeklySpendingHistory: samples
        )

        XCTAssertEqual(
            FinancialScenarioEngineV2.weeklySpendingAssumption(
                profile: profile,
                scenario: .conservative
            ),
            94.25,
            accuracy: 0.001
        )

        XCTAssertEqual(
            FinancialScenarioEngineV2.weeklySpendingAssumption(
                profile: profile,
                scenario: .expected
            ),
            91,
            accuracy: 0.001
        )

        XCTAssertEqual(
            FinancialScenarioEngineV2.weeklySpendingAssumption(
                profile: profile,
                scenario: .optimistic
            ),
            87.75,
            accuracy: 0.001
        )
    }

    func testIrregularIncomeChangesAcrossScenarios() throws {
        let asOf = makeDate(2026, 9, 1)
        let profile = makeProfile(
            currentCash: 1000,
            asOfDate: asOf,
            incomeEvents: [
                V2IncomeEvent(
                    amount: 1000,
                    date: makeDate(2026, 9, 10),
                    source: "Tutoring",
                    type: .irregular,
                    confidence: 0.6
                )
            ]
        )

        let target = makeDate(2026, 9, 15)

        let conservative = try FinancialScenarioEngineV2.forecast(
            profile: profile,
            targetDate: target,
            scenario: .conservative,
            calendar: calendar
        )
        let expected = try FinancialScenarioEngineV2.forecast(
            profile: profile,
            targetDate: target,
            scenario: .expected,
            calendar: calendar
        )
        let optimistic = try FinancialScenarioEngineV2.forecast(
            profile: profile,
            targetDate: target,
            scenario: .optimistic,
            calendar: calendar
        )

        XCTAssertEqual(conservative.forecast.expectedIncome, 0, accuracy: 0.001)
        XCTAssertEqual(expected.forecast.expectedIncome, 600, accuracy: 0.001)
        XCTAssertEqual(optimistic.forecast.expectedIncome, 1000, accuracy: 0.001)
    }

    func testPurchaseCanBeNotSafeTightAndSafeAcrossScenarios() throws {
        let asOf = makeDate(2026, 9, 1)
        let profile = makeProfile(
            currentCash: 1000,
            asOfDate: asOf,
            reserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            incomeEvents: [
                V2IncomeEvent(
                    amount: 300,
                    date: makeDate(2026, 9, 10),
                    source: "Possible side income",
                    type: .irregular,
                    confidence: 0.3
                )
            ],
            safetyBufferPolicy: SafetyBufferPolicy(
                weeksOfCoverage: 0,
                manualMinimum: 100
            )
        )

        let amount = 550.0
        let purchaseDate = makeDate(2026, 9, 15)
        let horizon = makeDate(2026, 9, 20)

        let conservative = try FinancialScenarioEngineV2.assessPurchase(
            profile: profile,
            amount: amount,
            purchaseDate: purchaseDate,
            planningHorizon: horizon,
            scenario: .conservative,
            calendar: calendar
        )
        let expected = try FinancialScenarioEngineV2.assessPurchase(
            profile: profile,
            amount: amount,
            purchaseDate: purchaseDate,
            planningHorizon: horizon,
            scenario: .expected,
            calendar: calendar
        )
        let optimistic = try FinancialScenarioEngineV2.assessPurchase(
            profile: profile,
            amount: amount,
            purchaseDate: purchaseDate,
            planningHorizon: horizon,
            scenario: .optimistic,
            calendar: calendar
        )

        XCTAssertEqual(conservative.assessment.status, .notSafe)
        XCTAssertEqual(expected.assessment.status, .tight)
        XCTAssertEqual(optimistic.assessment.status, .safe)

        XCTAssertEqual(conservative.assessment.shortfallToHardFloor, 50, accuracy: 0.001)
        XCTAssertEqual(expected.assessment.minimumHardHeadroomAfterPurchase, 40, accuracy: 0.001)
        XCTAssertEqual(optimistic.assessment.minimumRecommendedHeadroomAfterPurchase, 150, accuracy: 0.001)
    }

    func testKnownOneTimeIncomeDoesNotChangeAcrossScenarios() throws {
        let asOf = makeDate(2026, 9, 1)
        let profile = makeProfile(
            currentCash: 1000,
            asOfDate: asOf,
            incomeEvents: [
                V2IncomeEvent(
                    amount: 300,
                    date: makeDate(2026, 9, 10),
                    source: "Confirmed reimbursement",
                    type: .oneTime
                )
            ]
        )

        let results = try FinancialScenarioEngineV2.forecastAll(
            profile: profile,
            targetDate: makeDate(2026, 9, 15),
            calendar: calendar
        )

        XCTAssertEqual(results.count, 3)
        for result in results {
            XCTAssertEqual(result.forecast.expectedIncome, 300, accuracy: 0.001)
        }
    }
}
