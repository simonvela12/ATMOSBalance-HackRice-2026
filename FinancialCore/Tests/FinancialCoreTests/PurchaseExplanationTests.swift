import XCTest
@testable import FinancialCore

final class PurchaseExplanationTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testTightPurchaseExplainsSafetyBufferUse() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 900,
            asOfDate: asOf,
            institutionalMinimums: [
                InstitutionalMinimum(name: "Checking minimum", minimumBalance: 500, startDate: asOf)
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 200)
        )

        let result = try FinancialInsights.assessAndExplainPurchase(
            profile: profile,
            amount: 300,
            purchaseDate: date(2026, 9, 2),
            planningHorizon: date(2026, 9, 30),
            calendar: calendar
        )

        XCTAssertEqual(result.assessment.status, .tight)
        XCTAssertEqual(result.explanation.reason, .usesSafetyBuffer)
        XCTAssertEqual(result.explanation.projectedCashAfterPurchase, 600, accuracy: 0.001)
        XCTAssertEqual(result.explanation.hardFloor, 500, accuracy: 0.001)
        XCTAssertEqual(result.explanation.recommendedFloor, 700, accuracy: 0.001)
    }

    func testNotSafePurchaseCanIdentifyInstitutionalMinimum() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 900,
            asOfDate: asOf,
            institutionalMinimums: [
                InstitutionalMinimum(name: "Checking minimum", minimumBalance: 500, startDate: asOf)
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 100)
        )

        let result = try FinancialInsights.assessAndExplainPurchase(
            profile: profile,
            amount: 450,
            purchaseDate: date(2026, 9, 2),
            planningHorizon: date(2026, 9, 30),
            calendar: calendar
        )

        XCTAssertEqual(result.assessment.status, .notSafe)
        XCTAssertEqual(result.explanation.reason, .violatesInstitutionalMinimum)
        XCTAssertEqual(result.explanation.projectedCashAfterPurchase, 450, accuracy: 0.001)
        XCTAssertEqual(result.explanation.shortfallToHardFloor, 50, accuracy: 0.001)
    }

    func testNotSafePurchaseCanIdentifyPersonalReserve() throws {
        let asOf = date(2026, 9, 1)
        let profile = FinancialProfile(
            currentCash: 1200,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 1000)
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let result = try FinancialInsights.assessAndExplainPurchase(
            profile: profile,
            amount: 250,
            purchaseDate: date(2026, 9, 2),
            planningHorizon: date(2026, 9, 30),
            calendar: calendar
        )

        XCTAssertEqual(result.assessment.status, .notSafe)
        XCTAssertEqual(result.explanation.reason, .violatesPersonalReserve)
        XCTAssertEqual(result.explanation.projectedCashAfterPurchase, 950, accuracy: 0.001)
        XCTAssertEqual(result.explanation.shortfallToHardFloor, 50, accuracy: 0.001)
    }

    func testNotSafePurchaseExplainsProtectedGoalEvenOutsidePlanningHorizon() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            goals: [
                Goal(
                    name: "Miami",
                    targetAmount: 1000,
                    deadline: date(2026, 12, 26),
                    priority: .mandatory,
                    flexibility: .low
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        let result = try FinancialInsights.assessAndExplainPurchase(
            profile: profile,
            amount: 1500,
            purchaseDate: asOf,
            planningHorizon: date(2026, 11, 30),
            calendar: calendar
        )

        XCTAssertEqual(result.assessment.status, .notSafe)
        XCTAssertEqual(result.explanation.reason, .violatesProtectedGoal)
        XCTAssertEqual(result.explanation.hardFloor, 1000, accuracy: 0.001)
        XCTAssertEqual(result.explanation.projectedCashAfterPurchase, 850, accuracy: 0.001)
        XCTAssertEqual(result.explanation.shortfallToHardFloor, 150, accuracy: 0.001)
    }

    func testProtectedGoalAndPersonalReserveExplainMultipleHardConstraints() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [
                Goal(
                    name: "Miami",
                    targetAmount: 1000,
                    deadline: date(2026, 12, 26),
                    priority: .mandatory,
                    flexibility: .low
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        let result = try FinancialInsights.assessAndExplainPurchase(
            profile: profile,
            amount: 2000,
            purchaseDate: asOf,
            planningHorizon: date(2026, 11, 30),
            calendar: calendar
        )

        XCTAssertEqual(result.assessment.status, .notSafe)
        XCTAssertEqual(result.explanation.reason, .violatesMultipleHardConstraints)
    }
}
