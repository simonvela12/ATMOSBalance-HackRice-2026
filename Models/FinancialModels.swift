import Foundation

struct FinancialSummary: Equatable, Sendable {
    let currentCash: Double
    let protectedCash: Double
    let safeToSpendThroughNovember: Double
    let safeToSpendThisWeek: Double
}

struct FinancialGoal: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let targetAmount: Double
    let targetDate: Date

    init(id: UUID = UUID(), name: String, targetAmount: Double, targetDate: Date) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.targetDate = targetDate
    }
}

struct IncomeEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let amount: Double
    let date: Date

    init(id: UUID = UUID(), name: String, amount: Double, date: Date) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
    }
}

struct ExpenseEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let amount: Double
    let date: Date
    let isProtected: Bool

    init(id: UUID = UUID(), name: String, amount: Double, date: Date, isProtected: Bool = false) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.isProtected = isProtected
    }
}
