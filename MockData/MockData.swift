import Foundation

enum MockData {
    static let summary = FinancialSummary(
        currentCash: 8_000,
        protectedCash: 7_000,
        safeToSpendThroughNovember: 1_250,
        safeToSpendThisWeek: 87
    )

    static let goals: [FinancialGoal] = [
        FinancialGoal(name: "Miami Trip", targetAmount: 900, targetDate: date(month: 11, day: 14)),
        FinancialGoal(name: "F1 Ticket", targetAmount: 450, targetDate: date(month: 10, day: 23))
    ]

    static let incomeEvents: [IncomeEvent] = [
        IncomeEvent(name: "Paycheck", amount: 1_850, date: date(month: 9, day: 18)),
        IncomeEvent(name: "Paycheck", amount: 1_850, date: date(month: 10, day: 2))
    ]

    static let expenseEvents: [ExpenseEvent] = [
        ExpenseEvent(name: "Rent", amount: 1_350, date: date(month: 10, day: 1), isProtected: true),
        ExpenseEvent(name: "Utilities", amount: 165, date: date(month: 9, day: 22), isProtected: true),
        ExpenseEvent(name: "Groceries", amount: 120, date: date(month: 9, day: 19))
    ]

    private static func date(month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day)) ?? .now
    }
}
