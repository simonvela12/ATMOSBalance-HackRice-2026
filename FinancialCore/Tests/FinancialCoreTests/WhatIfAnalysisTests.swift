import XCTest
@testable import FinancialCore

final class WhatIfAnalysisTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testPurchaseCanMoveFlexibleGoalFromSafeToTight() throws {
        let asOf = date(2026, 9, 1)
        let miami = Goal(
            name: "Miami",
            targetAmount: 900,
            deadline: date(2026, 10, 1),
            priority: .flexible
        )
        let profile = FinancialProfile(
            currentCash: 2000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [miami],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 200)
        )

        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 500,
            purchaseDate: date(2026, 9, 10),
            planningHorizon: date(2026, 10, 2),
            calendar: calendar
        )

        XCTAssertEqual(result.goalImpacts.count, 1)
        XCTAssertEqual(result.goalImpacts[0].before.status, .safe)
        XCTAssertEqual(result.goalImpacts[0].after.status, .tight)
        XCTAssertTrue(result.goalImpacts[0].worsened)
        XCTAssertEqual(result.worsenedGoals.map { $0.goal.name }, ["Miami"])
    }

    func testPurchaseCanExposeMandatoryGoalShortfall() throws {
        let asOf = date(2026, 9, 1)
        let tuition = Goal(
            name: "Tuition",
            targetAmount: 700,
            deadline: date(2026, 10, 1),
            priority: .mandatory
        )
        let profile = FinancialProfile(
            currentCash: 1600,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [tuition],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 100)
        )

        let baseline = try FinancialInsights.assessGoalPlan(
            profile: profile,
            goal: tuition,
            planningHorizon: date(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(baseline.status, .safe)

        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 500,
            purchaseDate: date(2026, 9, 10),
            planningHorizon: date(2026, 10, 1),
            calendar: calendar
        )

        XCTAssertEqual(result.goalImpacts[0].before.status, .safe)
        XCTAssertEqual(result.goalImpacts[0].after.status, .notSafe)
        XCTAssertTrue(result.goalImpacts[0].worsened)
        XCTAssertEqual(result.goalImpacts[0].after.shortfallToHardFloor, 100, accuracy: 0.001)
    }

    func testSameDayWhatIfReducesCurrentCashRatherThanBeingIgnored() throws {
        let asOf = date(2026, 9, 1)
        let goal = Goal(
            name: "Trip",
            targetAmount: 500,
            deadline: date(2026, 9, 15),
            priority: .flexible
        )
        let profile = FinancialProfile(
            currentCash: 1200,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [goal],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 100)
        )

        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 200,
            purchaseDate: asOf,
            planningHorizon: date(2026, 9, 15),
            calendar: calendar
        )

        XCTAssertEqual(result.goalImpacts[0].before.status, .safe)
        XCTAssertEqual(result.goalImpacts[0].after.status, .tight)
        XCTAssertTrue(result.goalImpacts[0].worsened)
    }
}
