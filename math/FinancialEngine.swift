import Foundation

enum IncomeType: String, Codable {
    case recurring
    case irregular
    case oneTime
}

enum GoalPriority: String, Codable {
    case mandatory
    case flexible
}

struct IncomeEvent: Codable, Identifiable {
    let id: UUID
    let amount: Double
    let date: Date
    let source: String
    let type: IncomeType
    let confidence: Double

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        source: String,
        type: IncomeType,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.source = source
        self.type = type
        self.confidence = confidence
    }

    var adjustedAmount: Double {
        switch type {
        case .irregular:
            return amount * min(max(confidence, 0.0), 1.0)
        case .recurring, .oneTime:
            return amount
        }
    }
}

struct ExpenseEvent: Codable, Identifiable {
    let id: UUID
    let amount: Double
    let date: Date
    let category: String
    let essential: Bool
    let committed: Bool

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        category: String,
        essential: Bool = true,
        committed: Bool = true
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.category = category
        self.essential = essential
        self.committed = committed
    }
}

struct Goal: Codable, Identifiable {
    let id: UUID
    let name: String
    let targetAmount: Double
    let currentFundedAmount: Double
    let deadline: Date
    let priority: GoalPriority
    let alreadyProtected: Bool

    init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        currentFundedAmount: Double = 0,
        deadline: Date,
        priority: GoalPriority,
        alreadyProtected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currentFundedAmount = currentFundedAmount
        self.deadline = deadline
        self.priority = priority
        self.alreadyProtected = alreadyProtected
    }

    var remainingFunding: Double {
        max(0, targetAmount - currentFundedAmount)
    }
}

struct FinancialProfile: Codable {
    var currentCash: Double
    var protectedCash: Double
    var safetyBuffer: Double
    var asOfDate: Date
    var incomeEvents: [IncomeEvent]
    var expenseEvents: [ExpenseEvent]
    var goals: [Goal]
}

struct ForecastResult {
    let targetDate: Date
    let expectedIncome: Double
    let committedExpenses: Double
    let mandatoryGoalReserve: Double
    let projectedBalance: Double
    let protectedCash: Double
    let safetyBuffer: Double
    let safeToSpend: Double
}

struct PurchaseAssessment {
    enum Status: String {
        case safe = "SAFE"
        case wait = "WAIT"
    }

    let status: Status
    let purchaseAmount: Double
    let purchaseDate: Date
    let safeToSpendBeforePurchase: Double
    let remainingAfterPurchase: Double
    let shortfall: Double
    let recommendedDate: Date?
}

enum FinancialEngineError: Error {
    case targetDateBeforeProfileDate
    case negativePurchaseAmount
    case invalidDateRange
}

enum FinancialEngine {
    static func expectedIncome(
        profile: FinancialProfile,
        targetDate: Date
    ) -> Double {
        profile.incomeEvents
            .filter { $0.date > profile.asOfDate && $0.date <= targetDate }
            .reduce(0) { $0 + $1.adjustedAmount }
    }

    static func committedExpenses(
        profile: FinancialProfile,
        targetDate: Date
    ) -> Double {
        profile.expenseEvents
            .filter {
                $0.committed &&
                $0.date > profile.asOfDate &&
                $0.date <= targetDate
            }
            .reduce(0) { $0 + $1.amount }
    }

    static func mandatoryGoalReserve(
        profile: FinancialProfile,
        targetDate: Date
    ) -> Double {
        profile.goals
            .filter {
                $0.priority == .mandatory &&
                !$0.alreadyProtected &&
                $0.deadline <= targetDate
            }
            .reduce(0) { $0 + $1.remainingFunding }
    }

    static func forecast(
        profile: FinancialProfile,
        targetDate: Date
    ) throws -> ForecastResult {
        guard targetDate >= profile.asOfDate else {
            throw FinancialEngineError.targetDateBeforeProfileDate
        }

        let income = expectedIncome(profile: profile, targetDate: targetDate)
        let expenses = committedExpenses(profile: profile, targetDate: targetDate)
        let goalReserve = mandatoryGoalReserve(profile: profile, targetDate: targetDate)

        let projectedBalance = profile.currentCash + income - expenses
        let safeToSpend = projectedBalance
            - profile.protectedCash
            - profile.safetyBuffer
            - goalReserve

        return ForecastResult(
            targetDate: targetDate,
            expectedIncome: income,
            committedExpenses: expenses,
            mandatoryGoalReserve: goalReserve,
            projectedBalance: projectedBalance,
            protectedCash: profile.protectedCash,
            safetyBuffer: profile.safetyBuffer,
            safeToSpend: safeToSpend
        )
    }

    static func assessPurchase(
        profile: FinancialProfile,
        amount: Double,
        purchaseDate: Date,
        searchUntil: Date? = nil
    ) throws -> PurchaseAssessment {
        guard amount >= 0 else {
            throw FinancialEngineError.negativePurchaseAmount
        }

        let result = try forecast(profile: profile, targetDate: purchaseDate)
        let remaining = result.safeToSpend - amount
        let status: PurchaseAssessment.Status = remaining >= 0 ? .safe : .wait
        let shortfall = max(0, -remaining)

        var recommendedDate: Date? = nil
        if status == .wait, let searchUntil {
            recommendedDate = try earliestSafePurchaseDate(
                profile: profile,
                amount: amount,
                startDate: purchaseDate,
                endDate: searchUntil
            )
        }

        return PurchaseAssessment(
            status: status,
            purchaseAmount: amount,
            purchaseDate: purchaseDate,
            safeToSpendBeforePurchase: result.safeToSpend,
            remainingAfterPurchase: remaining,
            shortfall: shortfall,
            recommendedDate: recommendedDate
        )
    }

    static func earliestSafePurchaseDate(
        profile: FinancialProfile,
        amount: Double,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) throws -> Date? {
        guard endDate >= startDate else {
            throw FinancialEngineError.invalidDateRange
        }

        var currentDate = startDate
        while currentDate <= endDate {
            let result = try forecast(profile: profile, targetDate: currentDate)
            if result.safeToSpend >= amount {
                return currentDate
            }

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }

        return nil
    }
}
