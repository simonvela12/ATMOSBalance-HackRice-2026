import Foundation

struct FinancialSummary: Equatable, Sendable {
    let currentCash: Double
    let protectedCash: Double
    let safeToSpendThroughNovember: Double
    let safeToSpendThisWeek: Double
}

enum GoalPriority: Int, Codable, CaseIterable, Sendable {
    case high = 1
    case medium = 2
    case low = 3

    var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

struct FinancialGoal: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let targetAmount: Double
    let currentSaved: Double
    let targetDate: Date
    let priority: GoalPriority
    let plannedMonthlyContribution: Double
    let isProtected: Bool

    init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        currentSaved: Double = 0,
        targetDate: Date,
        priority: GoalPriority = .medium,
        plannedMonthlyContribution: Double = 0,
        isProtected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.targetAmount = max(0, targetAmount)
        self.currentSaved = max(0, min(currentSaved, targetAmount))
        self.targetDate = targetDate
        self.priority = priority
        self.plannedMonthlyContribution = max(0, plannedMonthlyContribution)
        self.isProtected = isProtected
    }

    var remainingAmount: Double {
        max(0, targetAmount - currentSaved)
    }

    var progress: Double {
        guard targetAmount > 0 else { return 1 }
        return min(1, currentSaved / targetAmount)
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
