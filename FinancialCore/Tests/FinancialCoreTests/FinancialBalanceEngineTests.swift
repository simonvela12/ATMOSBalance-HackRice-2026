import XCTest
@testable import FinancialCore

final class FinancialBalanceEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    }

    private func date(days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: today)!
    }

    func testTotalBalanceAndLiquidAccountBalanceAreSeparated() throws {
        let profile = FinancialProfile(currentCash: 1_500, asOfDate: today)
        let balances = [
            AccountBalanceSnapshot(id: "checking", name: "Checking", balance: 1_000, isLiquid: true),
            AccountBalanceSnapshot(id: "savings", name: "Savings", balance: 500, isLiquid: true),
            AccountBalanceSnapshot(id: "credit", name: "Credit Card", balance: -300, isLiquid: false)
        ]

        let summary = try FinancialBalanceEngine.summarize(
            profile: profile,
            accountBalances: balances,
            calendar: calendar
        )

        XCTAssertEqual(summary.totalBalance, 1_200, accuracy: 0.001)
        XCTAssertEqual(summary.liquidAccountBalance, 1_500, accuracy: 0.001)
    }

    func testLiquidBalanceProtectsReserveBillsAndSafetyBuffer() throws {
        let profile = FinancialProfile(
            currentCash: 2_000,
            asOfDate: today,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: today, minimumCash: 500, note: "Emergency reserve")
            ],
            expenseEvents: [
                ExpenseEvent(amount: 600, date: date(days: 10), category: "Rent", committed: true)
            ],
            weeklySpendingHistory: [
                WeeklySpendingSample(weekStart: date(days: -7), totalVariableSpending: 100)
            ],
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2)
        )

        let summary = try FinancialBalanceEngine.summarize(
            profile: profile,
            shortTermDays: 30,
            calendar: calendar
        )

        XCTAssertEqual(summary.protectedReserveThroughHorizon, 500, accuracy: 0.001)
        XCTAssertEqual(summary.safetyBuffer, 200, accuracy: 0.001)
        XCTAssertEqual(summary.committedExpensesDue, 600, accuracy: 0.001)
        XCTAssertEqual(summary.liquidBalanceBeforeGoalPlan, 700, accuracy: 0.001)
    }

    func testShortTermGoalContributionIsRecommendationNotAutomaticProgress() throws {
        let goal = Goal(
            name: "Laptop",
            targetAmount: 900,
            amountAlreadyPaid: 300,
            deadline: date(days: 60),
            priority: .medium,
            flexibility: .medium
        )
        let profile = FinancialProfile(
            currentCash: 2_000,
            asOfDate: today,
            goals: [goal],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let summary = try FinancialBalanceEngine.summarize(
            profile: profile,
            shortTermDays: 30,
            calendar: calendar
        )
        let contribution = try XCTUnwrap(summary.shortTermGoalContributions.first)

        XCTAssertEqual(goal.amountAlreadyPaid, 300, accuracy: 0.001)
        XCTAssertEqual(contribution.recommendedContribution, 300, accuracy: 0.001)
        XCTAssertEqual(contribution.remainingAmount, 600, accuracy: 0.001)
    }

    func testLowerThanExpectedRealContributionRaisesNextRecommendation() throws {
        let originalGoal = Goal(
            name: "Trip",
            targetAmount: 1_000,
            amountAlreadyPaid: 0,
            deadline: date(days: 100),
            priority: .medium,
            flexibility: .medium
        )
        let originalProfile = FinancialProfile(
            currentCash: 2_000,
            asOfDate: today,
            goals: [originalGoal],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )
        let originalHealth = try XCTUnwrap(
            SmartGoalEngine.evaluate(profile: originalProfile, calendar: calendar).goals.first
        )

        // Ten days later, the plan would have implied roughly $100 of progress, but
        // the user has only actually assigned/saved $50. We persist only that real
        // progress and let the engine recompute the recommendation from the new state.
        let tenDaysLater = date(days: 10)
        let updatedGoal = Goal(
            id: originalGoal.id,
            name: originalGoal.name,
            targetAmount: originalGoal.targetAmount,
            amountAlreadyPaid: 50,
            deadline: originalGoal.deadline,
            priority: originalGoal.priority,
            flexibility: originalGoal.flexibility
        )
        let updatedProfile = FinancialProfile(
            currentCash: 2_000,
            asOfDate: tenDaysLater,
            goals: [updatedGoal],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )
        let updatedHealth = try XCTUnwrap(
            SmartGoalEngine.evaluate(profile: updatedProfile, calendar: calendar).goals.first
        )

        XCTAssertEqual(originalHealth.requiredDailySavings, 10, accuracy: 0.001)
        XCTAssertGreaterThan(updatedHealth.requiredDailySavings, originalHealth.requiredDailySavings)
        XCTAssertEqual(updatedHealth.requiredDailySavings, 950.0 / 90.0, accuracy: 0.001)
    }

    func testMandatoryGoalDueSoonIsNotDoubleCounted() throws {
        let tuition = Goal(
            name: "Tuition",
            targetAmount: 500,
            deadline: date(days: 20),
            priority: .mandatory,
            flexibility: .low
        )
        let profile = FinancialProfile(
            currentCash: 1_500,
            asOfDate: today,
            goals: [tuition],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )

        let summary = try FinancialBalanceEngine.summarize(
            profile: profile,
            shortTermDays: 30,
            calendar: calendar
        )

        XCTAssertEqual(summary.mandatoryGoalPaymentsDue, 500, accuracy: 0.001)
        XCTAssertEqual(summary.shortTermGoalContributionTotal, 500, accuracy: 0.001)
        XCTAssertEqual(summary.additionalGoalContributionTotal, 0, accuracy: 0.001)
        XCTAssertEqual(summary.liquidBalanceAfterGoalPlan, 1_000, accuracy: 0.001)
    }
}

