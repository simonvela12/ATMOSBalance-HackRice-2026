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

    func testGoalCanWorsenWithoutChangingHealthBand() throws {
        let asOf = date(2026, 9, 1)
        let goal = Goal(
            name: "Trip",
            targetAmount: 400,
            deadline: date(2026, 9, 20),
            priority: .flexible
        )
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [goal],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 200)
        )

        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 50,
            purchaseDate: asOf,
            planningHorizon: date(2026, 9, 20),
            calendar: calendar
        )

        let impact = try XCTUnwrap(result.goalImpacts.first)
        XCTAssertEqual(impact.before.status, .tight)
        XCTAssertEqual(impact.after.status, .tight)
        XCTAssertEqual(impact.before.shortfallToRecommendedFloor, 100, accuracy: 0.001)
        XCTAssertEqual(impact.after.shortfallToRecommendedFloor, 150, accuracy: 0.001)
        XCTAssertTrue(impact.worsened)
        XCTAssertEqual(result.worsenedGoals.map { $0.goal.name }, ["Trip"])
    }

    func testUnchangedSameBandGoalIsNotReportedAsWorse() throws {
        let asOf = date(2026, 9, 1)
        let goal = Goal(
            name: "Trip",
            targetAmount: 400,
            deadline: date(2026, 9, 20),
            priority: .flexible
        )
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
            ],
            goals: [goal],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 200)
        )

        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 0,
            purchaseDate: asOf,
            planningHorizon: date(2026, 9, 20),
            calendar: calendar
        )

        let impact = try XCTUnwrap(result.goalImpacts.first)
        XCTAssertEqual(impact.before.status, .tight)
        XCTAssertEqual(impact.after.status, .tight)
        XCTAssertFalse(impact.worsened)
        XCTAssertTrue(result.worsenedGoals.isEmpty)
    }

    func testWhatIfUsesLiquidBalanceBeforeAProtectedGoalDeadline() throws {
        let asOf = date(2026, 9, 12)
        let miami = Goal(
            name: "Miami",
            targetAmount: 1000,
            deadline: date(2026, 12, 26),
            priority: .mandatory,
            flexibility: .fixed
        )
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            goals: [miami],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        // The What-If horizon intentionally ends before Miami. The purchase still
        // must not be allowed to consume Miami's protected $1,000.
        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 1500,
            purchaseDate: asOf,
            planningHorizon: date(2026, 11, 30),
            calendar: calendar
        )

        XCTAssertEqual(
            try FinancialEngine.liquidCashToday(profile: profile, calendar: calendar),
            1350,
            accuracy: 0.001
        )
        XCTAssertEqual(result.purchaseAssessment.status, .notSafe)
        XCTAssertEqual(result.purchaseAssessment.shortfallToHardFloor, 150, accuracy: 0.001)
        XCTAssertEqual(result.purchaseExplanation.reason, .violatesProtectedGoal)
    }

    /// A What-If has to answer with the whole picture: the headline number before and
    /// after, the runway, every scenario, and the constraint that binds.
    private func runwayProfile(cash: Double) -> FinancialProfile {
        let asOf = date(2026, 9, 12)
        let history = (0..<6).map { index in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                totalVariableSpending: 70
            )
        }
        return FinancialProfile(
            currentCash: cash,
            asOfDate: asOf,
            weeklySpendingHistory: history,
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0),
            cashMustLastUntil: calendar.date(byAdding: .day, value: 30, to: asOf)!
        )
    }

    func testWhatIfReportsBaselineAndScenarioForEveryDimension() throws {
        let profile = runwayProfile(cash: 1000)
        let asOf = profile.asOfDate

        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 180,
            purchaseDate: asOf,
            planningHorizon: calendar.date(byAdding: .day, value: 30, to: asOf)!,
            calendar: calendar
        )

        XCTAssertEqual(result.safeToSpendBefore.primary.amount, 700, accuracy: 0.001)
        XCTAssertEqual(result.safeToSpendAfter.primary.amount, 520, accuracy: 0.001)
        XCTAssertEqual(result.scenarioOutcomes.count, 3)
        XCTAssertEqual(
            result.scenarioOutcomes.map(\.scenario),
            [.conservative, .expected, .optimistic]
        )
        XCTAssertTrue(result.runwayBefore.isSatisfied)
        XCTAssertTrue(result.runwayAfter.isSatisfied)
        XCTAssertEqual(result.recommendation, .recommended)
    }

    func testWhatIfRefusesAPurchaseThatShortensTheRunway() throws {
        let profile = runwayProfile(cash: 1000)
        let asOf = profile.asOfDate

        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 900,
            purchaseDate: asOf,
            planningHorizon: calendar.date(byAdding: .day, value: 30, to: asOf)!,
            calendar: calendar
        )

        XCTAssertEqual(result.recommendation, .notRecommended)
        XCTAssertFalse(result.runwayAfter.isSatisfied)
        XCTAssertEqual(result.safeToSpendAfter.primary.amount, 0, accuracy: 0.001)
        XCTAssertNotNil(result.runwayAfter.projectedDepletionDate)

        let shift = try XCTUnwrap(result.runwayShiftInDays(calendar: calendar))
        XCTAssertLessThan(shift, 0)
    }

    func testWhatIfNamesTheUncertainIncomeAPurchaseWouldRelyOn() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 1000,
            asOfDate: asOf,
            incomeEvents: [
                IncomeEvent(
                    amount: 400,
                    date: date(2026, 9, 22),
                    source: "Freelance invoice",
                    type: .oneTime,
                    reliability: .uncertain
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 800,
                    date: date(2026, 10, 2),
                    category: "Tuition",
                    committed: true
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        let result = try FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: 300,
            purchaseDate: asOf,
            planningHorizon: date(2026, 10, 2),
            calendar: calendar
        )

        // The cautious answer says no; the expected answer only says yes because of a
        // payment that may not arrive, and the user has to be told which one.
        XCTAssertEqual(result.recommendation, .notRecommended)
        XCTAssertEqual(result.dependsOnUncertainIncome.count, 1)
        XCTAssertEqual(result.dependsOnUncertainIncome.first?.source, "Freelance invoice")
        XCTAssertEqual(result.dependsOnUncertainIncome.first?.reliability, .uncertain)
    }
}
