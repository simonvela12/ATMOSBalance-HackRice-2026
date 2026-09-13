import Foundation

public enum IncomeType: String, Codable, Sendable {
    case recurring
    case irregular
    case oneTime
}

public enum GoalPriority: String, Codable, CaseIterable, Hashable, Sendable {
    case mandatory
    case high
    case medium
    case low
    case flexible

    public var weight: Double {
        switch self {
        case .mandatory: 4
        case .high: 3
        case .medium: 2
        case .low: 1
        case .flexible: 0.75
        }
    }

    public var isProtected: Bool { self == .mandatory }
}

/// How far a goal's deadline may slide when the plan cannot honour every goal at
/// once. Flexibility is about the *date*, never the amount: the target amount is
/// fixed unless the user changes it.
public enum GoalFlexibility: Hashable, Sendable {
    /// The date cannot move. A fixed goal behaves like a dated obligation.
    case fixed
    /// The date may move forward by at most this many days.
    case maxDelay(days: Int)
    /// The goal has no real deadline, so it is the first one to yield.
    case openEnded

    /// Nil means "no upper bound"; zero means "cannot move at all".
    public var maximumDelayInDays: Int? {
        switch self {
        case .fixed: return 0
        case .maxDelay(let days): return max(0, days)
        case .openEnded: return nil
        }
    }

    public var allowsDelay: Bool { maximumDelayInDays != 0 }

    /// Higher means harder to move. Used when ranking which goals to protect first.
    public var protectionWeight: Double {
        switch self {
        case .fixed:
            return 1.5
        case .maxDelay(let days):
            if days <= 14 { return 1.2 }
            if days <= 60 { return 1.0 }
            return 0.8
        case .openEnded:
            return 0.6
        }
    }

    /// Choices a picker can offer. The enum itself cannot be `CaseIterable`
    /// because `maxDelay` carries a value.
    public static var presets: [GoalFlexibility] {
        [.fixed, .maxDelay(days: 14), .maxDelay(days: 30), .maxDelay(days: 60), .maxDelay(days: 180), .openEnded]
    }
}

extension GoalFlexibility: RawRepresentable {
    /// Persisted as a plain string so stored profiles stay a flat JSON document.
    /// Legacy `low`/`medium`/`high` values keep decoding into the closest new case.
    public init?(rawValue: String) {
        switch rawValue {
        case "fixed", "low":
            self = .fixed
        case "openEnded", "high":
            self = .openEnded
        case "medium":
            self = .maxDelay(days: 30)
        default:
            let prefix = "maxDelay:"
            guard rawValue.hasPrefix(prefix), let days = Int(rawValue.dropFirst(prefix.count)) else {
                return nil
            }
            self = .maxDelay(days: max(0, days))
        }
    }

    public var rawValue: String {
        switch self {
        case .fixed: return "fixed"
        case .openEnded: return "openEnded"
        case .maxDelay(let days): return "maxDelay:\(max(0, days))"
        }
    }
}

extension GoalFlexibility: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = GoalFlexibility(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised goal flexibility \"\(raw)\""
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// How much a future income event can be counted on. This is deliberately separate
/// from `IncomeType`: a recurring transfer from a parent is reliable, a freelance
/// invoice that is likely to be paid is expected, and a speculative gig is uncertain.
public enum IncomeReliability: String, Codable, CaseIterable, Hashable, Sendable {
    /// Salary, recurring transfers: money the plan may treat as certain.
    case reliable
    /// Highly likely, but not guaranteed.
    case expected
    /// Speculative. The conservative recommendation must not depend on it.
    case uncertain

    /// Fraction of the nominal amount a scenario is willing to count on.
    /// `confidence` only matters for income the user already marked uncertain.
    public func multiplier(for scenario: FinancialScenario, confidence: Double) -> Double {
        let bounded = min(max(confidence, 0), 1)
        switch self {
        case .reliable:
            return 1
        case .expected:
            switch scenario {
            case .conservative: return 0.5
            case .expected, .optimistic: return 1
            }
        case .uncertain:
            switch scenario {
            case .conservative: return 0
            case .expected: return bounded
            case .optimistic: return 1
            }
        }
    }

    /// True when a plan may lean on this money without a caveat.
    public var isGuaranteed: Bool { self == .reliable }
}

public enum GoalLifecycleState: String, Codable, Hashable, Sendable {
    case active
    case paused
    case completed
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
    /// How much of this money the plan is allowed to count on. When it is not set
    /// explicitly it is derived from `type`, so profiles written before reliability
    /// existed keep behaving exactly as they did.
    public let reliability: IncomeReliability
    public let amountRange: AmountRange?
    public let dateWindow: DateWindow?
    public let recurrenceRule: RecurrenceRule?
    public let allocations: [IncomeAllocation]?
    public let planningSource: PlanningEventSource?
    public let planningStatus: PlanningEventStatus?

    /// Recurring money is reliable, irregular money is uncertain. One-off payments
    /// the user entered deliberately are treated as reliable unless they say otherwise.
    public static func defaultReliability(for type: IncomeType) -> IncomeReliability {
        switch type {
        case .recurring, .oneTime: return .reliable
        case .irregular: return .uncertain
        }
    }

    public init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        source: String,
        type: IncomeType,
        confidence: Double = 1.0,
        reliability: IncomeReliability? = nil,
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
        self.reliability = reliability ?? IncomeEvent.defaultReliability(for: type)
        self.amountRange = amountRange
        self.dateWindow = dateWindow
        self.recurrenceRule = recurrenceRule
        self.allocations = allocations
        self.planningSource = planningSource
        self.planningStatus = planningStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        amount = try container.decode(Double.self, forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        source = try container.decode(String.self, forKey: .source)
        type = try container.decode(IncomeType.self, forKey: .type)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1.0
        reliability = try container.decodeIfPresent(IncomeReliability.self, forKey: .reliability)
            ?? IncomeEvent.defaultReliability(for: type)
        amountRange = try container.decodeIfPresent(AmountRange.self, forKey: .amountRange)
        dateWindow = try container.decodeIfPresent(DateWindow.self, forKey: .dateWindow)
        recurrenceRule = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrenceRule)
        allocations = try container.decodeIfPresent([IncomeAllocation].self, forKey: .allocations)
        planningSource = try container.decodeIfPresent(PlanningEventSource.self, forKey: .planningSource)
        planningStatus = try container.decodeIfPresent(PlanningEventStatus.self, forKey: .planningStatus)
    }

    /// The amount the baseline plan counts on. Reliability, not the raw type, decides
    /// how much of the nominal amount survives.
    public var adjustedAmount: Double {
        scenarioAdjustedAmount(for: .expected)
    }

    /// The amount a specific scenario is willing to count on.
    public func scenarioAdjustedAmount(for scenario: FinancialScenario) -> Double {
        amount * reliability.multiplier(for: scenario, confidence: confidence)
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
    /// Money that has **already left the balance** — a deposit paid, a booking settled.
    ///
    /// This is not "progress towards the goal". Money the user has mentally set aside
    /// but that is still sitting in their account has not been paid: it is still in
    /// `currentCash`, and the goal still costs its full price on its date. Subtracting
    /// it here as well would let the plan spend the same money twice.
    public let amountAlreadyPaid: Double
    public let deadline: Date
    public let priority: GoalPriority
    public let flexibility: GoalFlexibility
    public let lifecycleState: GoalLifecycleState

    public init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        amountAlreadyPaid: Double = 0,
        deadline: Date,
        priority: GoalPriority,
        flexibility: GoalFlexibility = .maxDelay(days: 30),
        lifecycleState: GoalLifecycleState = .active
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.amountAlreadyPaid = amountAlreadyPaid
        self.deadline = deadline
        self.priority = priority
        self.flexibility = flexibility
        self.lifecycleState = lifecycleState
    }

    /// A goal the user never gave a flexibility for: must-happen dates do not move,
    /// nice-to-have ones move freely, and everything else gets a month of slack.
    public static func defaultFlexibility(for priority: GoalPriority) -> GoalFlexibility {
        switch priority {
        case .mandatory: return .fixed
        case .flexible: return .openEnded
        case .high, .medium, .low: return .maxDelay(days: 30)
        }
    }

    public var remainingAmount: Double {
        max(0, targetAmount - amountAlreadyPaid)
    }

    public var currentAmount: Double { amountAlreadyPaid }
    public var targetDate: Date { deadline }

    public var isCompleted: Bool {
        lifecycleState == .completed || remainingAmount == 0
    }

    public init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        currentAmount: Double,
        targetDate: Date,
        priority: GoalPriority,
        flexibility: GoalFlexibility,
        lifecycleState: GoalLifecycleState = .active
    ) {
        self.init(
            id: id,
            name: name,
            targetAmount: targetAmount,
            amountAlreadyPaid: currentAmount,
            deadline: targetDate,
            priority: priority,
            flexibility: flexibility,
            lifecycleState: lifecycleState
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        targetAmount = try container.decode(Double.self, forKey: .targetAmount)
        amountAlreadyPaid = try container.decodeIfPresent(Double.self, forKey: .amountAlreadyPaid) ?? 0
        deadline = try container.decode(Date.self, forKey: .deadline)
        priority = try container.decodeIfPresent(GoalPriority.self, forKey: .priority) ?? .medium
        flexibility = try container.decodeIfPresent(GoalFlexibility.self, forKey: .flexibility) ??
            Goal.defaultFlexibility(for: priority)
        lifecycleState = try container.decodeIfPresent(GoalLifecycleState.self, forKey: .lifecycleState) ?? .active
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
    /// "My money has to last until this date." It is a viability requirement over the
    /// whole period, not a payment: nothing is ever deducted for it. The engine simply
    /// refuses to call money spendable if spending it would break the plan before then.
    public var cashMustLastUntil: Date?

    public init(
        currentCash: Double,
        asOfDate: Date,
        personalReserveSteps: [PersonalReserveStep] = [],
        institutionalMinimums: [InstitutionalMinimum] = [],
        incomeEvents: [IncomeEvent] = [],
        expenseEvents: [ExpenseEvent] = [],
        goals: [Goal] = [],
        weeklySpendingHistory: [WeeklySpendingSample] = [],
        spendingPolicy: SpendingPolicy = SpendingPolicy(),
        cashMustLastUntil: Date? = nil
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
        self.cashMustLastUntil = cashMustLastUntil
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
