import XCTest
@testable import FinancialCore

final class GoalInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testMandatoryGoalReportsFundingShortfall() throws {
        let asOf = date(2026, 9, 1)
        let goal = Goal(
            name: "Tuition",
            targetAmount: 900,
            deadline: date(2026, 10, 1),
            priority: .mandatory
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

        let result = try FinancialInsights.assessGoalPlan(
            profile: profile,
            goal: goal,
            planningHorizon: date(2026, 10, 1),
            calendar: calendar
        )

        XCTAssertEqual(result.status, .notSafe)
        XCTAssertTrue(result.includedInBaseline)
        XCTAssertEqual(result.shortfallToHardFloor, 200, accuracy: 0.001)
        XCTAssertEqual(result.shortfallToRecommendedFloor, 300, accuracy: 0.001)
        // Must-happen goals are protected from the as-of date onward, so the
        // shortfall is already real today rather than appearing on the deadline.
        XCTAssertEqual(result.tightestDate, asOf)
        XCTAssertEqual(result.effectiveDeadline, date(2026, 10, 1))
        XCTAssertNil(result.recommendedDate)

        // The same shortfall must still hold on the deadline, when the protected
        // goal converts into a mandatory payment. Protection must not double count.
        let atDeadline = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(2026, 10, 1),
            calendar: calendar
        )
        XCTAssertEqual(atDeadline.hardHeadroom, -200, accuracy: 0.001)
        XCTAssertEqual(atDeadline.recommendedHeadroom, -300, accuracy: 0.001)
    }

    func testFlexibleGoalAdaptsWhenNormalSpendingRises() throws {
        let asOf = date(2026, 9, 1)
        let deadline = date(2026, 9, 29)
        let goal = Goal(
            name: "Optional trip",
            targetAmount: 900,
            deadline: deadline,
            priority: .flexible
        )

        func profile(weeklySpend: Double) -> FinancialProfile {
            let history = (0..<6).map { index in
                WeeklySpendingSample(
                    weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                    totalVariableSpending: weeklySpend
                )
            }
            return FinancialProfile(
                currentCash: 2000,
                asOfDate: asOf,
                personalReserveSteps: [
                    PersonalReserveStep(effectiveDate: asOf, minimumCash: 500)
                ],
                goals: [goal],
                weeklySpendingHistory: history,
                spendingPolicy: SpendingPolicy(
                    lookbackWeeks: 6,
                    bufferWeeks: 2,
                    manualMinimumBuffer: 0
                )
            )
        }

        let lowerSpend = try FinancialInsights.assessGoalPlan(
            profile: profile(weeklySpend: 100),
            goal: goal,
            planningHorizon: deadline,
            calendar: calendar
        )
        let higherSpend = try FinancialInsights.assessGoalPlan(
            profile: profile(weeklySpend: 200),
            goal: goal,
            planningHorizon: deadline,
            calendar: calendar
        )

        XCTAssertEqual(lowerSpend.status, .safe)
        XCTAssertEqual(lowerSpend.shortfallToRecommendedFloor, 0, accuracy: 0.001)
        XCTAssertEqual(higherSpend.status, .notSafe)
        XCTAssertGreaterThan(higherSpend.shortfallToHardFloor, 0)
    }

    func testAssessAllGoalsReturnsDeadlineOrder() throws {
        let asOf = date(2026, 9, 1)
        let later = Goal(
            name: "Later goal",
            targetAmount: 100,
            deadline: date(2026, 12, 1),
            priority: .flexible
        )
        let sooner = Goal(
            name: "Sooner goal",
            targetAmount: 100,
            deadline: date(2026, 10, 1),
            priority: .flexible
        )
        let profile = FinancialProfile(
            currentCash: 2000,
            asOfDate: asOf,
            goals: [later, sooner],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let results = try FinancialInsights.assessAllGoals(
            profile: profile,
            planningHorizon: date(2026, 12, 31),
            calendar: calendar
        )

        XCTAssertEqual(results.map { $0.goal.name }, ["Sooner goal", "Later goal"])
    }
}
