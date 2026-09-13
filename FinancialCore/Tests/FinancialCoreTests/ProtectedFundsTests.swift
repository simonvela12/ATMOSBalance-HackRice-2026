import XCTest
@testable import FinancialCore

final class ProtectedFundsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testMandatoryGoalCommitsTodaysBalanceWhenNothingElseCanPayForIt() throws {
        let asOf = date(2026, 9, 12)
        let deadline = date(2026, 12, 26)
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            goals: [
                Goal(
                    name: "Miami",
                    targetAmount: 1000,
                    amountAlreadyPaid: 0,
                    deadline: deadline,
                    priority: .mandatory,
                    flexibility: .fixed
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        XCTAssertEqual(
            FinancialEngine.protectedMandatoryGoals(profile: profile, on: asOf),
            1000,
            accuracy: 0.001
        )

        // The goal is not part of the floor. It is a payment due in December, and with
        // no income before then today's balance is the only thing that can cover it —
        // which is what the forecast works out rather than what a reservation asserts.
        XCTAssertEqual(FinancialEngine.hardFloor(profile: profile, on: asOf), 0, accuracy: 0.001)
        XCTAssertEqual(
            try FinancialEngine.protectedCashToday(profile: profile, calendar: calendar),
            1000,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try FinancialEngine.liquidCashToday(profile: profile, calendar: calendar),
            1350,
            accuracy: 0.001
        )

        let today = try FinancialEngine.forecast(profile: profile, targetDate: asOf, calendar: calendar)
        XCTAssertEqual(today.projectedCash, 2350, accuracy: 0.001)
        XCTAssertEqual(today.hardFloor, 0, accuracy: 0.001)
        XCTAssertEqual(today.hardHeadroom, 2350, accuracy: 0.001)
    }

    func testFutureIncomeReleasesCashAGoalWouldOtherwiseCommit() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            incomeEvents: [
                IncomeEvent(
                    amount: 1200,
                    date: date(2026, 12, 1),
                    source: "Salary",
                    type: .recurring,
                    reliability: .reliable
                )
            ],
            goals: [
                Goal(
                    name: "Miami",
                    targetAmount: 1000,
                    deadline: date(2026, 12, 26),
                    priority: .mandatory,
                    flexibility: .fixed
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        // December's paycheck pays for Miami, so holding today's money back would be a
        // fiction. The whole balance is genuinely spendable.
        XCTAssertEqual(
            try FinancialEngine.liquidCashToday(profile: profile, calendar: calendar),
            2350,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try FinancialEngine.protectedCashToday(profile: profile, calendar: calendar),
            0,
            accuracy: 0.001
        )
    }

    func testProtectionBecomesPaymentOnDeadlineWithoutDoubleCounting() throws {
        let asOf = date(2026, 9, 12)
        let deadline = date(2026, 12, 26)
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            goals: [
                Goal(
                    name: "Miami",
                    targetAmount: 1000,
                    deadline: deadline,
                    priority: .mandatory,
                    flexibility: .fixed
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: deadline,
            calendar: calendar
        )

        XCTAssertEqual(result.mandatoryGoalPayments, 1000, accuracy: 0.001)
        XCTAssertEqual(result.projectedCash, 1350, accuracy: 0.001)
        XCTAssertEqual(result.hardFloor, 0, accuracy: 0.001)
        XCTAssertEqual(result.hardHeadroom, 1350, accuracy: 0.001)
    }

    func testPurchaseCannotConsumeProtectedGoalCashEvenBeforeGoalEntersPlanningHorizon() throws {
        let asOf = date(2026, 9, 12)
        let deadline = date(2026, 12, 26)
        let shortPlanningHorizon = date(2026, 11, 30)
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            goals: [
                Goal(
                    name: "Miami",
                    targetAmount: 1000,
                    deadline: deadline,
                    priority: .mandatory,
                    flexibility: .fixed
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        let tooLarge = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 1500,
            purchaseDate: asOf,
            planningHorizon: shortPlanningHorizon,
            calendar: calendar
        )
        XCTAssertEqual(tooLarge.status, .notSafe)
        XCTAssertEqual(tooLarge.shortfallToHardFloor, 150, accuracy: 0.001)

        let withinLiquidCash = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: 1300,
            purchaseDate: asOf,
            planningHorizon: shortPlanningHorizon,
            calendar: calendar
        )
        XCTAssertEqual(withinLiquidCash.status, .safe)
    }

    func testGoalDueTodayStillCountsAsProtectedCashToday() throws {
        let asOf = date(2026, 9, 12)
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            goals: [
                Goal(
                    name: "Tuition",
                    targetAmount: 1000,
                    deadline: asOf,
                    priority: .mandatory,
                    flexibility: .fixed
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        XCTAssertEqual(FinancialEngine.hardFloor(profile: profile, on: asOf), 0, accuracy: 0.001)
        XCTAssertEqual(
            try FinancialEngine.protectedCashToday(profile: profile, calendar: calendar),
            1000,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try FinancialEngine.liquidCashToday(profile: profile, calendar: calendar),
            1350,
            accuracy: 0.001
        )
    }

    func testPausedMandatoryGoalDoesNotProtectOrPayUntilResumed() throws {
        let asOf = date(2026, 9, 12)
        let deadline = date(2026, 12, 26)
        let profile = FinancialProfile(
            currentCash: 2350,
            asOfDate: asOf,
            goals: [
                Goal(
                    name: "Paused trip",
                    targetAmount: 1000,
                    deadline: deadline,
                    priority: .mandatory,
                    flexibility: .fixed,
                    lifecycleState: .paused
                )
            ],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0)
        )

        XCTAssertEqual(FinancialEngine.hardFloor(profile: profile, on: asOf), 0, accuracy: 0.001)
        XCTAssertEqual(
            try FinancialEngine.protectedCashToday(profile: profile, calendar: calendar),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try FinancialEngine.liquidCashToday(profile: profile, calendar: calendar),
            2350,
            accuracy: 0.001
        )

        let result = try FinancialEngine.forecast(
            profile: profile,
            targetDate: deadline,
            calendar: calendar
        )
        XCTAssertEqual(result.mandatoryGoalPayments, 0, accuracy: 0.001)
        XCTAssertEqual(result.projectedCash, 2350, accuracy: 0.001)
    }
}
