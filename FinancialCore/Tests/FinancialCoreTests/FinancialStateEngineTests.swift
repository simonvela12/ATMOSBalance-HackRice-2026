import XCTest
@testable import FinancialCore

/// Every transaction must update the whole financial state. Whether the user is shown
/// anything is a separate decision, so routine spending stays quiet.
final class FinancialStateEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let asOf = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: asOf)!
    }

    private func profile(
        cash: Double,
        income: [IncomeEvent] = [],
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
            goals: goals,
            weeklySpendingHistory: history,
            spendingPolicy: SpendingPolicy(bufferWeeks: 0, manualMinimumBuffer: 0),
            cashMustLastUntil: runway
        )
    }

    private func spend(_ amount: Double, label: String = "Purchase") -> RecordedTransaction {
        RecordedTransaction(amount: -amount, date: asOf, label: label)
    }

    // MARK: - Recalculation

    func testRecordingATransactionRecalculatesTheWholeState() throws {
        let base = profile(cash: 1000, runway: day(30), weeklySpending: 70)
        let change = try FinancialStateEngine.apply(
            spend(180),
            to: base,
            calendar: calendar
        )

        XCTAssertEqual(change.profile.currentCash, 820, accuracy: 0.001)
        XCTAssertEqual(change.before.safeToSpendToday, 700, accuracy: 0.001)
        XCTAssertEqual(change.after.safeToSpendToday, 520, accuracy: 0.001)
        XCTAssertEqual(change.safeToSpendChange, -180, accuracy: 0.001)

        // The rest of the state moves with it rather than going stale.
        XCTAssertEqual(change.after.safeToSpend.all.count, 3)
        XCTAssertEqual(change.after.dashboard.asOfDate, asOf)
        XCTAssertEqual(change.after.planningHorizon, day(30))
        XCTAssertLessThan(
            change.after.dashboard.safeToSpendNow,
            change.before.dashboard.safeToSpendNow
        )
    }

    func testSmallTransactionUpdatesTheNumbersWithoutRaisingAWarning() throws {
        let base = profile(cash: 1000, runway: day(30), weeklySpending: 70)
        let change = try FinancialStateEngine.apply(
            spend(6, label: "Coffee"),
            to: base,
            calendar: calendar
        )

        // The state is always recomputed...
        XCTAssertEqual(change.after.safeToSpendToday, 694, accuracy: 0.001)
        XCTAssertEqual(change.safeToSpendChange, -6, accuracy: 0.001)

        // ...but a six-dollar coffee is not worth interrupting anyone for.
        XCTAssertEqual(change.materiality, .ignoreNoImpact)
        XCTAssertFalse(change.isMaterial)
        XCTAssertTrue(change.newWarnings.isEmpty)
        XCTAssertTrue(change.goalDateChanges.allSatisfy { !$0.moved })
    }

    func testMaterialTransactionIsSurfaced() throws {
        let base = profile(cash: 1000, runway: day(30), weeklySpending: 70)
        let change = try FinancialStateEngine.apply(
            spend(180),
            to: base,
            calendar: calendar
        )

        XCTAssertEqual(change.materiality, .askUser)
        XCTAssertTrue(change.isMaterial)
    }

    func testMaterialTransactionThatMovesAGoalReportsTheNewDate() throws {
        let miami = Goal(
            name: "Miami",
            targetAmount: 400,
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
        let base = profile(
            cash: 1000,
            income: [
                IncomeEvent(
                    amount: 600,
                    date: day(60),
                    source: "Salary",
                    type: .recurring,
                    reliability: .reliable
                )
            ],
            goals: [miami, laptop]
        )

        let change = try FinancialStateEngine.apply(
            spend(200),
            to: base,
            calendar: calendar
        )

        let laptopChange = try XCTUnwrap(
            change.goalDateChanges.first { $0.goalID == laptop.id }
        )
        XCTAssertEqual(laptopChange.statusBefore, .onTrack)
        XCTAssertEqual(laptopChange.statusAfter, .adjusted)
        XCTAssertEqual(laptopChange.dateBefore, day(40))
        XCTAssertEqual(laptopChange.dateAfter, day(60))
        XCTAssertEqual(laptopChange.shiftInDays, 20)

        // Miami is the reason the laptop moved, so it must not move itself.
        let miamiChange = try XCTUnwrap(
            change.goalDateChanges.first { $0.goalID == miami.id }
        )
        XCTAssertFalse(miamiChange.moved)

        XCTAssertTrue(change.isMaterial)
        XCTAssertTrue(
            change.newWarnings.contains { warning in
                if case .goalDelayed(let id, _) = warning.kind { return id == laptop.id }
                return false
            }
        )
    }

    func testTransactionThatShortensTheRunwayIsAlwaysSurfaced() throws {
        let base = profile(cash: 1000, runway: day(30), weeklySpending: 70)
        let change = try FinancialStateEngine.apply(
            spend(900),
            to: base,
            calendar: calendar
        )

        XCTAssertTrue(change.before.runway.isSatisfied)
        XCTAssertFalse(change.after.runway.isSatisfied)
        XCTAssertEqual(change.runwayShiftInDays, -20)
        XCTAssertTrue(change.isMaterial)
        XCTAssertTrue(
            change.newWarnings.contains { warning in
                if case .runwayAtRisk = warning.kind { return true }
                return false
            }
        )
    }

    func testFutureTransactionBecomesADatedEventRatherThanChangingTodaysBalance() throws {
        let base = profile(cash: 1000, runway: day(30), weeklySpending: 70)
        let updated = base.applying(
            RecordedTransaction(amount: -200, date: day(15), label: "Flight")
        )

        XCTAssertEqual(updated.currentCash, 1000, accuracy: 0.001)
        XCTAssertEqual(updated.expenseEvents.count, 1)
        XCTAssertEqual(updated.expenseEvents.first?.date, day(15))
    }

    func testTransactionsApplyInSequenceWithStateRecalculatedEachTime() throws {
        let base = profile(cash: 1000, runway: day(30), weeklySpending: 70)
        let changes = try FinancialStateEngine.apply(
            [spend(100), spend(100)],
            to: base,
            calendar: calendar
        )

        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].after.safeToSpendToday, 600, accuracy: 0.001)
        XCTAssertEqual(changes[1].before.safeToSpendToday, 600, accuracy: 0.001)
        XCTAssertEqual(changes[1].after.safeToSpendToday, 500, accuracy: 0.001)
        XCTAssertEqual(changes[1].profile.currentCash, 800, accuracy: 0.001)
    }
}
