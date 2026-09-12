import Foundation

public enum IncomeType: String, Codable, Sendable {
    case recurring
    case irregular
    case oneTime
}

public enum GoalPriority: String, Codable, Sendable {
    case mandatory
    case flexible
}

public enum PurchaseStatus: String, Codable, Sendable {
    case safe = "SAFE"
    case tight = "TIGHT"
    case notSafe = "NOT_SAFE"
}

public enum FinancialScenario: String, Codable, CaseIterable, Sendable {
    case conservative = "CONSERVATIVE"
    case expected = "EXPECTED"
    case optimistic = "OPTIMISTIC"
}

public struct IncomeEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let amount: Double
    public let date: Date
    public let source: String
    public let type: IncomeType
    public let confidence: Double
    public let amountRange: AmountRange?
    public let dateWindow: DateWindow?
    public let recurrenceRule: RecurrenceRule?
    public let allocations: [IncomeAllocation]?
    public let planningSource: PlanningEventSource?
    public let planningStatus: PlanningEventStatus?

    public init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        source: String,
        type: IncomeType,
        confidence: Double = 1.0,
        amountRange: AmountRange? = nil,
        dateWindow: DateWindow? = nil,
        recurrenceRule: RecurrenceRule? = nil,
        allocations: [IncomeAllocation]? = nil,
        planningSource: PlanningEventSource? = nil,
        planningStatus: PlanningEventStatus? = nil
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.source = source
        self.type = type
        self.confidence = confidence
        self.amountRange = amountRange
        self.dateWindow = dateWindow
        self.recurrenceRule = recurrenceRule
        self.allocations = allocations
        self.planningSource = planningSource
        self.planningStatus = planningStatus
    }

    public var adjustedAmount: Double {
        switch type {
        case .irregular:
            return amount * min(max(confidence, 0), 1)
        case .recurring, .oneTime:
            return amount
        }
    }
}

public struct ExpenseEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let amount: Double
    public let date: Date
    public let category: String
    public let essential: Bool
    public let committed: Bool
    public let reimbursable: Bool
    public let extraordinary: Bool
    public let amountRange: AmountRange?
    public let dateWindow: DateWindow?
    public let recurrenceRule: RecurrenceRule?
    public let merchantIdentity: String?
    public let planningSource: PlanningEventSource?
    public let planningStatus: PlanningEventStatus?

    public init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        category: String,
        essential: Bool = true,
        committed: Bool = true,
        reimbursable: Bool = false,
        extraordinary: Bool = false,
        amountRange: AmountRange? = nil,
        dateWindow: DateWindow? = nil,
        recurrenceRule: RecurrenceRule? = nil,
        merchantIdentity: String? = nil,
        planningSource: PlanningEventSource? = nil,
        planningStatus: PlanningEventStatus? = nil
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.category = category
        self.essential = essential
        self.committed = committed
        self.reimbursable = reimbursable
        self.extraordinary = extraordinary
        self.amountRange = amountRange
        self.dateWindow = dateWindow
        self.recurrenceRule = recurrenceRule
        self.merchantIdentity = merchantIdentity
        self.planningSource = planningSource
        self.planningStatus = planningStatus
    }
}

public struct Goal: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let targetAmount: Double
    public let amountAlreadyPaid: Double
    public let deadline: Date
    public let priority: GoalPriority

    public init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        amountAlreadyPaid: Double = 0,
        deadline: Date,
        priority: GoalPriority
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.amountAlreadyPaid = amountAlreadyPaid
        self.deadline = deadline
        self.priority = priority
    }

    public var remainingAmount: Double {
        max(0, targetAmount - amountAlreadyPaid)
    }
}

public struct PersonalReserveStep: Codable, Identifiable, Sendable {
    public let id: UUID
    public let effectiveDate: Date
    public let minimumCash: Double
    public let note: String

    public init(
        id: UUID = UUID(),
        effectiveDate: Date,
        minimumCash: Double,
        note: String = ""
    ) {
        self.id = id
        self.effectiveDate = effectiveDate
        self.minimumCash = minimumCash
        self.note = note
    }
}

public struct InstitutionalMinimum: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let minimumBalance: Double
    public let startDate: Date
    public let endDate: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        minimumBalance: Double,
        startDate: Date,
        endDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.minimumBalance = minimumBalance
        self.startDate = startDate
        self.endDate = endDate
    }

    public func isActive(on date: Date) -> Bool {
        guard date >= startDate else { return false }
        if let endDate, date > endDate { return false }
        return true
    }
}

public struct WeeklySpendingSample: Codable, Identifiable, Sendable {
    public let id: UUID
    public let weekStart: Date
    public let totalVariableSpending: Double
    public let excludedFromBaseline: Bool

    public init(
        id: UUID = UUID(),
        weekStart: Date,
        totalVariableSpending: Double,
        excludedFromBaseline: Bool = false
    ) {
        self.id = id
        self.weekStart = weekStart
        self.totalVariableSpending = totalVariableSpending
        self.excludedFromBaseline = excludedFromBaseline
    }
}

public struct SpendingPolicy: Codable, Sendable {
    public var lookbackWeeks: Int
    public var bufferWeeks: Double
    public var manualMinimumBuffer: Double

    public init(
        lookbackWeeks: Int = 6,
        bufferWeeks: Double = 2.0,
        manualMinimumBuffer: Double = 0
    ) {
        self.lookbackWeeks = lookbackWeeks
        self.bufferWeeks = bufferWeeks
        self.manualMinimumBuffer = manualMinimumBuffer
    }
}

public struct FinancialProfile: Codable, Sendable {
    public var currentCash: Double
    public var asOfDate: Date
    public var personalReserveSteps: [PersonalReserveStep]
    public var institutionalMinimums: [InstitutionalMinimum]
    public var incomeEvents: [IncomeEvent]
    public var expenseEvents: [ExpenseEvent]
    public var goals: [Goal]
    public var weeklySpendingHistory: [WeeklySpendingSample]
    public var spendingPolicy: SpendingPolicy

    public init(
        currentCash: Double,
        asOfDate: Date,
        personalReserveSteps: [PersonalReserveStep] = [],
        institutionalMinimums: [InstitutionalMinimum] = [],
        incomeEvents: [IncomeEvent] = [],
        expenseEvents: [ExpenseEvent] = [],
        goals: [Goal] = [],
        weeklySpendingHistory: [WeeklySpendingSample] = [],
        spendingPolicy: SpendingPolicy = SpendingPolicy()
    ) {
        self.currentCash = currentCash
        self.asOfDate = asOfDate
        self.personalReserveSteps = personalReserveSteps
        self.institutionalMinimums = institutionalMinimums
        self.incomeEvents = incomeEvents
        self.expenseEvents = expenseEvents
        self.goals = goals
        self.weeklySpendingHistory = weeklySpendingHistory
        self.spendingPolicy = spendingPolicy
    }
}

public struct ForecastResult: Sendable {
    public let targetDate: Date
    public let expectedIncome: Double
    public let committedExpenses: Double
    public let projectedVariableSpending: Double
    public let mandatoryGoalPayments: Double
    public let projectedCash: Double
    public let personalReserve: Double
    public let institutionalMinimum: Double
    public let hardFloor: Double
    public let safetyBuffer: Double
    public let hardHeadroom: Double
    public let recommendedHeadroom: Double
}

public struct HorizonHeadroom: Sendable {
    public let startDate: Date
    public let endDate: Date
    public let minimumHardHeadroom: Double
    public let minimumRecommendedHeadroom: Double
    public let tightestHardDate: Date
    public let tightestRecommendedDate: Date
}

public struct PurchaseAssessment: Sendable {
    public let status: PurchaseStatus
    public let purchaseAmount: Double
    public let purchaseDate: Date
    public let planningHorizon: Date
    public let minimumHardHeadroomBeforePurchase: Double
    public let minimumRecommendedHeadroomBeforePurchase: Double
    public let minimumHardHeadroomAfterPurchase: Double
    public let minimumRecommendedHeadroomAfterPurchase: Double
    public let shortfallToHardFloor: Double
    public let shortfallToRecommendedFloor: Double
    public let tightestHardDate: Date
    public let tightestRecommendedDate: Date
    public let recommendedDate: Date?
}

public struct FlexibleGoalAssessment: Sendable {
    public let goal: Goal
    public let purchaseAssessment: PurchaseAssessment
}

public struct ScenarioForecastResult: Sendable {
    public let scenario: FinancialScenario
    public let weeklySpendingAssumption: Double
    public let forecast: ForecastResult
}

public struct ScenarioPurchaseResult: Sendable {
    public let scenario: FinancialScenario
    public let weeklySpendingAssumption: Double
    public let assessment: PurchaseAssessment
}

public enum FinancialEngineError: Error, Equatable, Sendable {
    case targetDateBeforeProfileDate
    case invalidDateRange
    case negativeAmount
}
