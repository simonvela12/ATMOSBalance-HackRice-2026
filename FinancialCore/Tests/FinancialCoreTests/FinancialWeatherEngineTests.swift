import XCTest
@testable import FinancialCore

final class FinancialWeatherEngineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
    }

    private func profile(cash: Double, weeklySpend: Double, income: Double = 0, expense: Double = 0) -> FinancialProfile {
        let history = (1...6).map {
            WeeklySpendingSample(weekStart: calendar.date(byAdding: .weekOfYear, value: -$0, to: today)!, totalVariableSpending: weeklySpend)
        }
        let end = calendar.date(byAdding: .day, value: 30, to: today)!
        return FinancialProfile(
            currentCash: cash,
            asOfDate: today,
            incomeEvents: income > 0 ? [IncomeEvent(amount: income, date: end, source: "Income", type: .oneTime)] : [],
            expenseEvents: expense > 0 ? [ExpenseEvent(amount: expense, date: end, category: "Bill")] : [],
            weeklySpendingHistory: history,
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )
    }

    func testSameBalanceProducesDifferentWeatherForDifferentSpendingNeeds() throws {
        let lowNeeds = try FinancialWeatherEngine.assess(profile: profile(cash: 2_000, weeklySpend: 100), calendar: calendar)
        let highNeeds = try FinancialWeatherEngine.assess(profile: profile(cash: 2_000, weeklySpend: 600), calendar: calendar)
        XCTAssertGreaterThan(lowNeeds.score, highNeeds.score)
        XCTAssertNotEqual(lowNeeds.state, highNeeds.state)
    }

    func testFutureDipCapsWeatherEvenWhenLaterIncomeRecoversBalance() throws {
        let expenseDate = calendar.date(byAdding: .day, value: 10, to: today)!
        let incomeDate = calendar.date(byAdding: .day, value: 20, to: today)!
        let profile = FinancialProfile(
            currentCash: 1_000,
            asOfDate: today,
            personalReserveSteps: [PersonalReserveStep(effectiveDate: today, minimumCash: 500)],
            incomeEvents: [IncomeEvent(amount: 1_000, date: incomeDate, source: "Pay", type: .oneTime)],
            expenseEvents: [ExpenseEvent(amount: 800, date: expenseDate, category: "Rent")],
            spendingPolicy: SpendingPolicy(bufferWeeks: 0)
        )
        let result = try FinancialWeatherEngine.assess(profile: profile, calendar: calendar)
        XCTAssertTrue(result.state == .storm || result.state == .rain)
    }

    func testMissingFinancialHistoryDefaultsToCloudy() throws {
        let result = try FinancialWeatherEngine.assess(
            profile: FinancialProfile(currentCash: 10_000, asOfDate: today),
            calendar: calendar
        )
        XCTAssertEqual(result.state, .cloudy)
        XCTAssertFalse(result.hasEnoughData)
    }
}
