import XCTest
@testable import FinancialCore

final class ReimbursementLiquidityPathTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    func testLaterReimbursementDoesNotEraseEarlierLiquidityDip() throws {
        let profile = FinancialProfile(
            currentCash: 700,
            asOfDate: date(12),
            personalReserveSteps: [
                PersonalReserveStep(
                    effectiveDate: date(12),
                    minimumCash: 500,
                    note: "Protected cash"
                )
            ],
            incomeEvents: [
                IncomeEvent(
                    amount: 300,
                    date: date(20),
                    source: "Reimbursement: Group dinner",
                    type: .oneTime,
                    confidence: 1
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 300,
                    date: date(14),
                    category: "Group dinner",
                    essential: false,
                    committed: true
                )
            ],
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 0,
                bufferWeeks: 0,
                manualMinimumBuffer: 0
            )
        )

        let beforeRepayment = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(15),
            calendar: calendar
        )
        let afterRepayment = try FinancialEngine.forecast(
            profile: profile,
            targetDate: date(20),
            calendar: calendar
        )
        let horizon = try FinancialEngine.minimumHeadroom(
            profile: profile,
            from: date(12),
            through: date(20),
            calendar: calendar
        )
        let safeToSpend = try FinancialEngine.safeToSpend(
            profile: profile,
            from: date(12),
            through: date(20),
            calendar: calendar
        )

        XCTAssertEqual(beforeRepayment.projectedCash, 400, accuracy: 0.000_001)
        XCTAssertEqual(beforeRepayment.hardHeadroom, -100, accuracy: 0.000_001)
        XCTAssertEqual(afterRepayment.projectedCash, 700, accuracy: 0.000_001)
        XCTAssertEqual(horizon.minimumHardHeadroom, -100, accuracy: 0.000_001)
        XCTAssertEqual(horizon.tightestHardDate, date(14))
        XCTAssertEqual(safeToSpend, 0, accuracy: 0.000_001)
    }

    func testSameAmountReimbursementBeforeExpenseDoesNotCreateFalseDip() throws {
        let profile = FinancialProfile(
            currentCash: 700,
            asOfDate: date(12),
            personalReserveSteps: [
                PersonalReserveStep(
                    effectiveDate: date(12),
                    minimumCash: 500,
                    note: "Protected cash"
                )
            ],
            incomeEvents: [
                IncomeEvent(
                    amount: 300,
                    date: date(13),
                    source: "Reimbursement: Group dinner",
                    type: .oneTime,
                    confidence: 1
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 300,
                    date: date(14),
                    category: "Group dinner",
                    essential: false,
                    committed: true
                )
            ],
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 0,
                bufferWeeks: 0,
                manualMinimumBuffer: 0
            )
        )

        let horizon = try FinancialEngine.minimumHeadroom(
            profile: profile,
            from: date(12),
            through: date(20),
            calendar: calendar
        )

        XCTAssertEqual(horizon.minimumHardHeadroom, 200, accuracy: 0.000_001)
    }
}
