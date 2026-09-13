import XCTest
@testable import FinancialCore

/// Covers the model the product is built on: goals are dated requirements rather than
/// savings buckets, and Safe to Spend is whatever survives simulating the plan forward.
final class SafeToSpendEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let asOf = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: asOf)!
    }

    /// No reserve, no buffer and no spending history, so every number in a test comes
    /// from the events that test declares.
    private func profile(
        cash: Double,
        income: [IncomeEvent] = [],
        expenses: [ExpenseEvent] = [],
        goals: [Goal] = [],
        runway: Date? = nil,
        weeklySpending: Double? = nil
    ) -> FinancialProfile {
        var history: [WeeklySpendingSample] = []
        if let weeklySpending {
            history = (0..<6).map { index in
                WeeklySpendingSample(
                    weekStart: calendar.date(byAdding: .day, value: -(index * 7), to: asOf)!,
                    totalVariableSpending: weeklySpending
                )
            }
        }

        return FinancialProfile(
            currentCash: cash,
            asOfDate: asOf,
            incomeEvents: income,
            expenseEvents: expenses,
            goals: goals,
            weeklySpendingHistory: history,
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0),
            cashMustLastUntil: runway
        )
    }

    private func expense(_ amount: Double, _ offset: Int) -> ExpenseEvent {
        ExpenseEvent(amount: amount, date: day(offset), category: "Rent", committed: true)
    }

    private func income(
        _ amount: Double,
        _ offset: Int,
        _ reliability: IncomeReliability,
        confidence: Double = 1
    ) -> IncomeEvent {
        IncomeEvent(
            amount: amount,
            date: day(offset),
            source: "Payment",
            type: .oneTime,
            confidence: confidence,
            reliability: reliability
        )
    }

    // MARK: - Income reliability

    func testReliableAndUncertainIncomeProduceDifferentSafeToSpend() throws {
        let reliable = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 1000,
                income: [income(500, 10, .reliable)],
                expenses: [expense(800, 20)]
            ),
            scenario: .conservative,
            calendar: calendar
        )
        let uncertain = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 1000,
                income: [income(500, 10, .uncertain)],
                expenses: [expense(800, 20)]
            ),
            scenario: .conservative,
            calendar: calendar
        )

        // Money that is certain to arrive can be planned against; money that is not
        // cannot, so the same nominal income yields a very different answer.
        XCTAssertEqual(reliable.amount, 700, accuracy: 0.001)
        XCTAssertEqual(uncertain.amount, 200, accuracy: 0.001)
    }

    func testConservativeScenarioIgnoresUncertainIncomeAndDiscountsExpectedIncome() throws {
        let uncertain = profile(
            cash: 1000,
            income: [income(500, 10, .uncertain)],
            expenses: [expense(800, 20)]
        )
        let expected = profile(
            cash: 1000,
            income: [income(500, 10, .expected)],
            expenses: [expense(800, 20)]
        )

        let uncertainResults = try SafeToSpendEngine.evaluateAllScenarios(
            profile: uncertain,
            calendar: calendar
        )
        let expectedResults = try SafeToSpendEngine.evaluateAllScenarios(
            profile: expected,
            calendar: calendar
        )

        // Speculative money is worth nothing to the cautious answer.
        XCTAssertEqual(uncertainResults.conservative.amount, 200, accuracy: 0.001)
        XCTAssertEqual(uncertainResults.expected.amount, 700, accuracy: 0.001)

        // Likely money is heavily discounted rather than ignored outright.
        XCTAssertEqual(expectedResults.conservative.amount, 450, accuracy: 0.001)
        XCTAssertEqual(expectedResults.expected.amount, 700, accuracy: 0.001)

        // The cautious number is the one the product leads with.
        XCTAssertEqual(uncertainResults.primary.amount, uncertainResults.conservative.amount)
    }

    func testScenariosProduceDistinctResultsWhenAssumptionsDiffer() throws {
        let results = try SafeToSpendEngine.evaluateAllScenarios(
            profile: profile(
                cash: 1000,
                income: [
                    income(400, 10, .uncertain, confidence: 0.5),
                    income(300, 10, .expected)
                ],
                expenses: [expense(800, 20)]
            ),
            calendar: calendar
        )

        XCTAssertEqual(results.conservative.amount, 350, accuracy: 0.001)
        XCTAssertEqual(results.expected.amount, 700, accuracy: 0.001)
        XCTAssertEqual(results.optimistic.amount, 900, accuracy: 0.001)
        XCTAssertEqual(results.conservative.scenario, .conservative)
        XCTAssertEqual(results.result(for: .optimistic).scenario, .optimistic)
    }

    func testPlanThatLeansOnUncertainIncomeSaysSo() throws {
        let result = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 1000,
                income: [income(500, 10, .uncertain)],
                expenses: [expense(800, 20)]
            ),
            scenario: .expected,
            calendar: calendar
        )

        // The expected scenario counts the payment, so the answer is only valid if it
        // actually turns up. That has to be visible rather than implied.
        XCTAssertEqual(result.amount, 700, accuracy: 0.001)
        XCTAssertEqual(result.dependsOnUncertainIncome.count, 1)
        XCTAssertEqual(result.dependsOnUncertainIncome.first?.amount, 500)
        XCTAssertEqual(result.dependsOnUncertainIncome.first?.reliability, .uncertain)
    }

    func testReliableIncomeIsNeverReportedAsADependency() throws {
        let result = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 1000,
                income: [income(500, 10, .reliable)],
                expenses: [expense(800, 20)]
            ),
            scenario: .expected,
            calendar: calendar
        )

        XCTAssertTrue(result.dependsOnUncertainIncome.isEmpty)
    }

    // MARK: - Runway

    func testRunwayDateReducesSafeToSpend() throws {
        let withoutRunway = try SafeToSpendEngine.evaluate(
            profile: profile(cash: 1000, weeklySpending: 70),
            calendar: calendar
        )
        let withRunway = try SafeToSpendEngine.evaluate(
            profile: profile(cash: 1000, runway: day(30), weeklySpending: 70),
            calendar: calendar
        )

        // Asking the money to last 30 more days means 30 days of spending has to be
        // covered out of today's balance.
        XCTAssertEqual(withoutRunway.amount, 1000, accuracy: 0.001)
        XCTAssertEqual(withRunway.amount, 700, accuracy: 0.001)
        XCTAssertEqual(withRunway.runway.requestedDate, day(30))
        XCTAssertTrue(withRunway.runway.isSatisfied)
    }

    func testRunwayIsEvaluatedAcrossTheWholeTimelineRatherThanAtItsEndDate() throws {
        // A dip in the middle that later income repairs. Checking only the end date
        // would report a comfortable balance and miss the dip entirely.
        let result = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 1000,
                income: [income(500, 20, .reliable)],
                expenses: [expense(900, 10)],
                runway: day(30)
            ),
            calendar: calendar
        )

        XCTAssertEqual(result.amount, 100, accuracy: 0.001)
        XCTAssertEqual(result.limitingDate, day(10))
        XCTAssertNil(result.runway.projectedDepletionDate)
        XCTAssertTrue(result.runway.isSatisfied)

        // Cash on the final day is far higher than what is actually spendable, which is
        // exactly what an end-point-only check would have returned.
        let atRunwayEnd = try FinancialEngine.forecast(
            profile: profile(
                cash: 1000,
                income: [income(500, 20, .reliable)],
                expenses: [expense(900, 10)],
                runway: day(30)
            ),
            targetDate: day(30),
            calendar: calendar
        )
        XCTAssertEqual(atRunwayEnd.projectedCash, 600, accuracy: 0.001)
    }

    func testRunwayReportsTheDayTheMoneyRunsOutEvenWhenLaterIncomeRecovers() throws {
        let result = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 1000,
                income: [income(500, 20, .reliable)],
                expenses: [expense(1100, 10)],
                runway: day(30)
            ),
            calendar: calendar
        )

        XCTAssertFalse(result.runway.isSatisfied)
        XCTAssertEqual(result.runway.projectedDepletionDate, day(10))
        XCTAssertEqual(result.runway.viableThrough, day(9))
        XCTAssertEqual(result.runway.shortfall, 100, accuracy: 0.001)
        XCTAssertEqual(result.amount, 0, accuracy: 0.001)
        XCTAssertEqual(result.status, .notSafe)
    }

    // MARK: - Goals as dated requirements

    func testFutureIncomeMeansAGoalDoesNotImmobiliseTodaysBalance() throws {
        let miami = Goal(
            name: "Miami",
            targetAmount: 1000,
            deadline: day(100),
            priority: .mandatory,
            flexibility: .fixed
        )

        let withoutIncome = try SafeToSpendEngine.evaluate(
            profile: profile(cash: 2350, goals: [miami]),
            calendar: calendar
        )
        let withIncome = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 2350,
                income: [income(1200, 90, .reliable)],
                goals: [miami]
            ),
            calendar: calendar
        )

        // With nothing coming in, today's balance is the only thing that can pay for
        // Miami, so $1,000 of it is genuinely committed.
        XCTAssertEqual(withoutIncome.amount, 1350, accuracy: 0.001)
        XCTAssertEqual(withoutIncome.futureCommitments, 1000, accuracy: 0.001)

        // Once a paycheck covers the goal, holding today's cash back would be a fiction.
        XCTAssertEqual(withIncome.amount, 2350, accuracy: 0.001)
        XCTAssertEqual(withIncome.futureCommitments, 0, accuracy: 0.001)
    }

    func testBalanceBreakdownAddsUp() throws {
        let result = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 2350,
                goals: [
                    Goal(
                        name: "Miami",
                        targetAmount: 1000,
                        deadline: day(100),
                        priority: .mandatory,
                        flexibility: .fixed
                    )
                ]
            ),
            calendar: calendar
        )

        // The panel shows balance, commitments, buffer and the headline figure. Those
        // four have to reconstruct the balance exactly or the breakdown reads as wrong.
        XCTAssertEqual(
            result.amount + result.safetyReserve + result.futureCommitments,
            result.totalBalance,
            accuracy: 0.001
        )
    }

    func testFlexibleGoalMovesSoAProtectedGoalKeepsItsDate() throws {
        let miami = Goal(
            name: "Miami",
            targetAmount: 700,
            deadline: day(30),
            priority: .mandatory,
            flexibility: .fixed
        )
        let laptop = Goal(
            name: "Laptop",
            targetAmount: 500,
            deadline: day(40),
            priority: .low,
            flexibility: .maxDelay(days: 60)
        )

        let result = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 1000,
                income: [income(600, 60, .reliable)],
                goals: [miami, laptop]
            ),
            calendar: calendar
        )

        let miamiProjection = try XCTUnwrap(
            result.goalProjections.first { $0.goal.id == miami.id }
        )
        let laptopProjection = try XCTUnwrap(
            result.goalProjections.first { $0.goal.id == laptop.id }
        )

        XCTAssertEqual(miamiProjection.status, .onTrack)
        XCTAssertEqual(miamiProjection.projectedDate, day(30))

        // The laptop waits for the paycheck rather than being pushed to the far end of
        // the allowance it happens to have.
        XCTAssertEqual(laptopProjection.status, .adjusted)
        XCTAssertEqual(laptopProjection.projectedDate, day(60))
        XCTAssertEqual(laptopProjection.delayInDays, 20)

        let conflict = try XCTUnwrap(result.conflicts.first { $0.goalID == laptop.id })
        XCTAssertEqual(conflict.resolution, .delayed(days: 20))
        XCTAssertEqual(conflict.preservedGoalIDs, [miami.id])

        XCTAssertEqual(result.amount, 300, accuracy: 0.001)
    }

    func testAFixedGoalThatCannotBeMetLeavesNothingSafeToSpend() throws {
        let tuition = Goal(
            name: "Tuition",
            targetAmount: 1500,
            deadline: day(20),
            priority: .mandatory,
            flexibility: .fixed
        )

        let result = try SafeToSpendEngine.evaluate(
            profile: profile(cash: 1000, goals: [tuition]),
            calendar: calendar
        )

        // Abandoning the goal would free up cash, which would be inventing spending
        // capacity the user does not have.
        XCTAssertEqual(result.amount, 0, accuracy: 0.001)
        XCTAssertEqual(result.status, .notSafe)
        XCTAssertEqual(result.unreachableGoals.map(\.goal.id), [tuition.id])
        XCTAssertEqual(
            result.limitingConstraint,
            .goalDeadline(goalID: tuition.id, date: day(20))
        )
    }

    func testAmountAlreadyPaidMeansMoneyThatLeftTheBalance() throws {
        // One real situation, described two ways. A $600 goal where $200 has genuinely
        // been paid: the balance is down to $800 and $400 is left to find.
        let partlyPaid = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 800,
                goals: [
                    Goal(
                        name: "Miami",
                        targetAmount: 600,
                        amountAlreadyPaid: 200,
                        deadline: day(40),
                        priority: .mandatory,
                        flexibility: .fixed
                    )
                ]
            ),
            calendar: calendar
        )

        // The same goal before anything is paid: the $200 is still in the balance and
        // the trip still costs $600.
        let nothingPaid = try SafeToSpendEngine.evaluate(
            profile: profile(
                cash: 1000,
                goals: [
                    Goal(
                        name: "Miami",
                        targetAmount: 600,
                        deadline: day(40),
                        priority: .mandatory,
                        flexibility: .fixed
                    )
                ]
            ),
            calendar: calendar
        )

        // Both descriptions have to produce the same answer. Treating savings that are
        // still in the account as "already paid" would report $600 here and let the
        // user spend the same $200 twice.
        XCTAssertEqual(partlyPaid.amount, 400, accuracy: 0.001)
        XCTAssertEqual(nothingPaid.amount, 400, accuracy: 0.001)
    }

    func testGoalDeadlineIsNamedAsTheLimitingConstraint() throws {
        let miami = Goal(
            name: "Miami",
            targetAmount: 1000,
            deadline: day(40),
            priority: .mandatory,
            flexibility: .fixed
        )
        let result = try SafeToSpendEngine.evaluate(
            profile: profile(cash: 1200, goals: [miami], runway: day(60)),
            calendar: calendar
        )

        XCTAssertEqual(result.amount, 200, accuracy: 0.001)
        XCTAssertEqual(
            result.limitingConstraint,
            .goalDeadline(goalID: miami.id, date: day(40))
        )
    }
}
