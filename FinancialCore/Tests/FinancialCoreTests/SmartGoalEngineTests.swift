import XCTest
@testable import FinancialCore

final class SmartGoalEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    }

    private func date(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: today)!
    }

    private func goal(
        _ name: String = "Goal",
        target: Double = 1_000,
        current: Double = 0,
        days: Int = 30,
        priority: GoalPriority = .medium,
        flexibility: GoalFlexibility = .medium,
        state: GoalLifecycleState = .active
    ) -> Goal {
        Goal(name: name, targetAmount: target, amountAlreadyPaid: current,
             deadline: date(days), priority: priority, flexibility: flexibility,
             lifecycleState: state)
    }

    private func profile(cash: Double, goals: [Goal], history: [WeeklySpendingSample] = []) -> FinancialProfile {
        FinancialProfile(currentCash: cash, asOfDate: today, goals: goals,
                         weeklySpendingHistory: history,
                         spendingPolicy: SpendingPolicy(bufferWeeks: 0))
    }

    func testGoalOnTrackWhenFundingArrivesAtDeadline() throws {
        let item = goal()
        var input = profile(cash: 0, goals: [item])
        input.incomeEvents = [IncomeEvent(amount: 1_000, date: item.deadline,
                                          source: "Pay", type: .oneTime)]
        let health = try XCTUnwrap(SmartGoalEngine.evaluate(profile: input, calendar: calendar).goals.first)
        XCTAssertEqual(health.status, .onTrack)
        XCTAssertEqual(health.projectedAmountAtDeadline, 1_000, accuracy: 0.001)
    }

    func testGoalAhead() throws {
        let health = try XCTUnwrap(SmartGoalEngine.evaluate(
            profile: profile(cash: 1_000, goals: [goal(days: 90)]), calendar: calendar
        ).goals.first)
        XCTAssertEqual(health.status, .ahead)
        XCTAssertGreaterThan(health.daysAheadOrBehind ?? 0, 7)
    }

    func testGoalBehind() throws {
        let health = try XCTUnwrap(SmartGoalEngine.evaluate(
            profile: profile(cash: 950, goals: [goal()]), calendar: calendar
        ).goals.first)
        XCTAssertEqual(health.status, .behind)
        XCTAssertEqual(health.shortfall, 50, accuracy: 0.001)
    }

    func testGoalAtRisk() throws {
        let health = try XCTUnwrap(SmartGoalEngine.evaluate(
            profile: profile(cash: 800, goals: [goal()]), calendar: calendar
        ).goals.first)
        XCTAssertEqual(health.status, .atRisk)
    }

    func testHealthyFourThousandIncomeThreeThousandExpensesScenario() throws {
        let item = goal("Six month goal", target: 3_000, days: 180)
        var input = profile(cash: 0, goals: [item])
        for month in 1...6 {
            let paymentDate = calendar.date(byAdding: .month, value: month, to: today)!
            input.incomeEvents.append(IncomeEvent(
                amount: 4_000, date: paymentDate, source: "Salary", type: .recurring
            ))
            input.expenseEvents.append(ExpenseEvent(
                amount: 3_000, date: paymentDate, category: "Living costs", committed: true
            ))
        }
        let result = try SmartGoalEngine.evaluate(profile: input, calendar: calendar)
        XCTAssertTrue(result.allGoalsAchievable)
        XCTAssertTrue([GoalStatus.ahead, .onTrack].contains(result.goals[0].status))
        XCTAssertEqual(result.goals[0].projectedAmountAtDeadline, 3_000, accuracy: 0.001)
    }

    func testGoalUnrealistic() throws {
        let health = try XCTUnwrap(SmartGoalEngine.evaluate(
            profile: profile(cash: 0, goals: [goal()]), calendar: calendar
        ).goals.first)
        XCTAssertEqual(health.status, .unrealistic)
        XCTAssertEqual(health.requiredAdditionalSavings, 1_000, accuracy: 0.001)
    }

    func testCompletedAndPausedAreManualStates() throws {
        let complete = goal("Done", current: 1_000)
        let paused = goal("Later", state: .paused)
        let result = try SmartGoalEngine.evaluate(profile: profile(cash: 0, goals: [complete, paused]), calendar: calendar)
        XCTAssertEqual(result.goals.first(where: { $0.goal.name == "Done" })?.status, .completed)
        XCTAssertEqual(result.goals.first(where: { $0.goal.name == "Later" })?.status, .paused)
    }

    func testUnexpectedExpenseDelaysGoalAndReducesSafeToSpend() throws {
        let input = profile(cash: 1_600, goals: [goal(days: 90)])
        let result = try SmartGoalEngine.impact(
            of: GoalCashMovement(amount: -800, date: today, label: "Dining"),
            on: input, calendar: calendar
        )
        XCTAssertLessThan(result.safeToSpendChange, 0)
        XCTAssertEqual(result.goalImpacts.first?.statusAfter, .atRisk)
        XCTAssertGreaterThan(result.goalImpacts.first?.shortfallChange ?? 0, 0)
    }

    func testUnexpectedIncomeImprovesGoal() throws {
        let input = profile(cash: 0, goals: [goal(days: 90)])
        let result = try SmartGoalEngine.impact(
            of: GoalCashMovement(amount: 1_000, date: today, label: "Bonus"),
            on: input, calendar: calendar
        )
        XCTAssertEqual(result.goalImpacts.first?.statusBefore, .unrealistic)
        XCTAssertEqual(result.goalImpacts.first?.statusAfter, .ahead)
        XCTAssertLessThan(result.goalImpacts.first?.shortfallChange ?? 0, 0)
    }

    func testConflictingGoalsProtectHigherPriority() throws {
        let emergency = goal("Emergency", target: 400, priority: .high, flexibility: .low)
        let laptop = goal("Laptop", target: 300, priority: .low, flexibility: .high)
        let result = try SmartGoalEngine.evaluate(
            profile: profile(cash: 500, goals: [laptop, emergency]), calendar: calendar
        )
        let emergencyHealth = try XCTUnwrap(result.goals.first { $0.goal.name == "Emergency" })
        let laptopHealth = try XCTUnwrap(result.goals.first { $0.goal.name == "Laptop" })
        XCTAssertEqual(emergencyHealth.shortfall, 0, accuracy: 0.001)
        XCTAssertEqual(laptopHealth.shortfall, 200, accuracy: 0.001)
        XCTAssertEqual(result.status, .conflicted)
        XCTAssertEqual(result.priorityGoalID, emergency.id)
        XCTAssertEqual(result.recommendedGoalToDelayID, laptop.id)
    }

    func testLowFlexibilityWinsWhenPrioritiesMatch() throws {
        let rigid = goal("Rigid", target: 400, priority: .medium, flexibility: .low)
        let flexible = goal("Flexible", target: 400, priority: .medium, flexibility: .high)
        let result = try SmartGoalEngine.evaluate(
            profile: profile(cash: 500, goals: [flexible, rigid]), calendar: calendar
        )
        XCTAssertEqual(result.priorityGoalID, rigid.id)
        XCTAssertEqual(result.goals.first(where: { $0.goal.id == rigid.id })?.shortfall, 0)
        XCTAssertGreaterThan(result.goals.first(where: { $0.goal.id == flexible.id })?.shortfall ?? 0, 0)
    }

    func testFlexibleUnrealisticGoalGetsAlternativeDate() throws {
        let item = goal(target: 1_000, priority: .low, flexibility: .high)
        let health = try XCTUnwrap(SmartGoalEngine.evaluate(
            profile: profile(cash: 500, goals: [item]), calendar: calendar
        ).goals.first)
        XCTAssertEqual(health.status, .unrealistic)
        XCTAssertNotNil(health.recommendedTargetDate)
        XCTAssertGreaterThan(health.recommendedTargetDate!, item.deadline)
    }

    func testPassedTargetDateIsUnrealistic() throws {
        let health = try XCTUnwrap(SmartGoalEngine.evaluate(
            profile: profile(cash: 1_000, goals: [goal(days: -1)]), calendar: calendar
        ).goals.first)
        XCTAssertEqual(health.status, .unrealistic)
    }

    func testNoTransactionHistoryIsDeterministic() throws {
        let result = try SmartGoalEngine.evaluate(
            profile: profile(cash: 1_200, goals: [goal()]), calendar: calendar
        )
        XCTAssertEqual(result.goals.count, 1)
        XCTAssertEqual(result.safeToSpendToday, 200, accuracy: 0.001)
    }

    func testNormalizedCashFromMultipleAccountsFundsPortfolioOnce() throws {
        let checking = 700.0
        let savings = 500.0
        let result = try SmartGoalEngine.evaluate(
            profile: profile(cash: checking + savings, goals: [goal()]), calendar: calendar
        )
        XCTAssertTrue(result.allGoalsAchievable)
        XCTAssertEqual(result.safeToSpendToday, 200, accuracy: 0.001)
    }

    func testDailyBehaviorAggregatesMovementsBeforeRecalculation() throws {
        let input = profile(cash: 1_200, goals: [goal(days: 90)])
        let result = try SmartGoalEngine.impact(of: [
            GoalCashMovement(amount: -100, date: today, label: "Food"),
            GoalCashMovement(amount: 50, date: today, label: "Refund")
        ], on: input, calendar: calendar)
        XCTAssertEqual(result.safeToSpendChange, -50, accuracy: 0.001)
    }

    func testGoalPersistenceContainsInputsButNotDerivedHealth() throws {
        let item = goal("Persisted", current: 250, priority: .high, flexibility: .low,
                        state: .paused)
        let data = try JSONEncoder().encode(item)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("priority"))
        XCTAssertTrue(json.contains("flexibility"))
        XCTAssertTrue(json.contains("lifecycleState"))
        XCTAssertFalse(json.contains("projectedCompletionDate"))
        XCTAssertFalse(json.contains("status"))
        let decoded = try JSONDecoder().decode(Goal.self, from: data)
        XCTAssertEqual(decoded.priority, .high)
        XCTAssertEqual(decoded.flexibility, .low)
        XCTAssertEqual(decoded.lifecycleState, .paused)
    }
}

