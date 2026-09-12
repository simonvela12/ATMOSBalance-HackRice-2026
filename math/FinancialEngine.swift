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

    init(id: UUID = UUID(), amount: Double, date: Date, source: String, type: IncomeType, confidence: Double = 1.0) {
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

    init(id: UUID = UUID(), amount: Double, date: Date, category: String, essential: Bool = true, committed: Bool = true) {
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

    init(id: UUID = UUID(), name: String, targetAmount: Double, currentFundedAmount: Double = 0, deadline: Date, priority: GoalPriority, alreadyProtected: Bool = false) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currentFundedAmount = currentFundedAmount
        self.deadline = deadline
        self.priority = priority
        self.alreadyProtected = alreadyProtected
    }

    var remainingFunding: Double { max(0, targetAmount - currentFundedAmount) }
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
    enum Status: String { case safe = "SAFE"; case wait = "WAIT" }
    let status: Status
    let purchaseAmount: Double
    let purchaseDate: Date
    let planningHorizon: Date
    let safeToSpendOnPurchaseDate: Double
    let minimumSafeToSpendThroughHorizon: Double
    let remainingAtTightestPoint: Double
    let shortfall: Double
    let recommendedDate: Date?
}

enum GoalStatus: String { case onTrack = "ON_TRACK"; case atRisk = "AT_RISK" }

struct GoalAssessment {
    let goal: Goal
    let status: GoalStatus
    let availableCapacityAtDeadline: Double
    let shortfall: Double
    let requiredWeeklyContribution: Double
}

enum FinancialHealth: String { case green = "GREEN"; case yellow = "YELLOW"; case red = "RED" }
enum AdherenceStatus: String { case green = "GREEN"; case yellow = "YELLOW"; case red = "RED" }

enum FinancialEngineError: Error {
    case targetDateBeforeProfileDate
    case negativePurchaseAmount
    case invalidDateRange
}

enum FinancialEngine {
    static func expectedIncome(profile: FinancialProfile, targetDate: Date) -> Double {
        profile.incomeEvents
            .filter { $0.date > profile.asOfDate && $0.date <= targetDate }
            .reduce(0) { $0 + $1.adjustedAmount }
    }

    static func committedExpenses(profile: FinancialProfile, targetDate: Date) -> Double {
        profile.expenseEvents
            .filter { $0.committed && $0.date > profile.asOfDate && $0.date <= targetDate }
            .reduce(0) { $0 + $1.amount }
    }

    static func mandatoryGoalReserve(profile: FinancialProfile, targetDate: Date) -> Double {
        profile.goals
            .filter { $0.priority == .mandatory && !$0.alreadyProtected && $0.deadline <= targetDate }
            .reduce(0) { $0 + $1.remainingFunding }
    }

    static func forecast(profile: FinancialProfile, targetDate: Date) throws -> ForecastResult {
        guard targetDate >= profile.asOfDate else { throw FinancialEngineError.targetDateBeforeProfileDate }
        let income = expectedIncome(profile: profile, targetDate: targetDate)
        let expenses = committedExpenses(profile: profile, targetDate: targetDate)
        let goalReserve = mandatoryGoalReserve(profile: profile, targetDate: targetDate)
        let projectedBalance = profile.currentCash + income - expenses
        let safeToSpend = projectedBalance - profile.protectedCash - profile.safetyBuffer - goalReserve
        return ForecastResult(targetDate: targetDate, expectedIncome: income, committedExpenses: expenses, mandatoryGoalReserve: goalReserve, projectedBalance: projectedBalance, protectedCash: profile.protectedCash, safetyBuffer: profile.safetyBuffer, safeToSpend: safeToSpend)
    }

    static func minimumSafeToSpend(profile: FinancialProfile, from startDate: Date, through endDate: Date, calendar: Calendar = .current) throws -> Double {
        guard endDate >= startDate else { throw FinancialEngineError.invalidDateRange }
        var currentDate = startDate
        var minimumValue = Double.greatestFiniteMagnitude
        while currentDate <= endDate {
            minimumValue = min(minimumValue, try forecast(profile: profile, targetDate: currentDate).safeToSpend)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        return minimumValue
    }

    static func assessPurchase(profile: FinancialProfile, amount: Double, purchaseDate: Date, planningHorizon: Date, calendar: Calendar = .current) throws -> PurchaseAssessment {
        guard amount >= 0 else { throw FinancialEngineError.negativePurchaseAmount }
        guard planningHorizon >= purchaseDate else { throw FinancialEngineError.invalidDateRange }
        let purchaseDateForecast = try forecast(profile: profile, targetDate: purchaseDate)
        let tightest = try minimumSafeToSpend(profile: profile, from: purchaseDate, through: planningHorizon, calendar: calendar)
        let remaining = tightest - amount
        let status: PurchaseAssessment.Status = remaining >= 0 ? .safe : .wait
        let shortfall = max(0, -remaining)
        let recommendedDate = status == .wait ? try earliestSafePurchaseDate(profile: profile, amount: amount, startDate: purchaseDate, planningHorizon: planningHorizon, calendar: calendar) : nil
        return PurchaseAssessment(status: status, purchaseAmount: amount, purchaseDate: purchaseDate, planningHorizon: planningHorizon, safeToSpendOnPurchaseDate: purchaseDateForecast.safeToSpend, minimumSafeToSpendThroughHorizon: tightest, remainingAtTightestPoint: remaining, shortfall: shortfall, recommendedDate: recommendedDate)
    }

    static func earliestSafePurchaseDate(profile: FinancialProfile, amount: Double, startDate: Date, planningHorizon: Date, calendar: Calendar = .current) throws -> Date? {
        guard planningHorizon >= startDate else { throw FinancialEngineError.invalidDateRange }
        var candidate = startDate
        while candidate <= planningHorizon {
            if try minimumSafeToSpend(profile: profile, from: candidate, through: planningHorizon, calendar: calendar) >= amount { return candidate }
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
            candidate = next
        }
        return nil
    }

    static func assessGoal(profile: FinancialProfile, goal: Goal, calendar: Calendar = .current) throws -> GoalAssessment {
        let days = max(1, calendar.dateComponents([.day], from: profile.asOfDate, to: goal.deadline).day ?? 1)
        let weeks = max(1.0, Double(days) / 7.0)
        let weekly = goal.remainingFunding / weeks

        if goal.alreadyProtected {
            return GoalAssessment(goal: goal, status: .onTrack, availableCapacityAtDeadline: goal.remainingFunding, shortfall: 0, requiredWeeklyContribution: 0)
        }

        let deadlineForecast = try forecast(profile: profile, targetDate: goal.deadline)
        let capacity = goal.priority == .mandatory ? deadlineForecast.safeToSpend + goal.remainingFunding : deadlineForecast.safeToSpend
        let shortfall = max(0, goal.remainingFunding - capacity)
        return GoalAssessment(goal: goal, status: shortfall == 0 ? .onTrack : .atRisk, availableCapacityAtDeadline: capacity, shortfall: shortfall, requiredWeeklyContribution: weekly)
    }

    static func safeWeeklyAllowance(profile: FinancialProfile, startDate: Date, planningHorizon: Date, calendar: Calendar = .current, iterations: Int = 30) throws -> Double {
        guard planningHorizon >= startDate else { throw FinancialEngineError.invalidDateRange }
        let totalDays = max(1, calendar.dateComponents([.day], from: startDate, to: planningHorizon).day ?? 1)
        let numberOfWeeks = max(1, Int(ceil(Double(totalDays + 1) / 7.0)))
        let baselineCapacity = max(0, try minimumSafeToSpend(profile: profile, from: startDate, through: planningHorizon, calendar: calendar))
        var low = 0.0
        var high = max(baselineCapacity, try forecast(profile: profile, targetDate: planningHorizon).safeToSpend) / Double(numberOfWeeks)
        high = max(high, 1.0)

        func canSustain(_ weekly: Double) throws -> Bool {
            var temp = profile
            var spendDate = startDate
            if spendDate <= profile.asOfDate {
                spendDate = calendar.date(byAdding: .day, value: 1, to: profile.asOfDate) ?? spendDate
            }
            for i in 0..<numberOfWeeks {
                if i > 0 {
                    guard let next = calendar.date(byAdding: .day, value: 7, to: spendDate) else { break }
                    spendDate = next
                }
                if spendDate > planningHorizon { break }
                temp.expenseEvents.append(ExpenseEvent(amount: weekly, date: spendDate, category: "Recommended discretionary allowance", essential: false, committed: true))
            }
            return try minimumSafeToSpend(profile: temp, from: startDate, through: planningHorizon, calendar: calendar) >= -0.0001
        }

        while try canSustain(high) && high < 100_000 { high *= 2 }
        for _ in 0..<iterations {
            let mid = (low + high) / 2
            if try canSustain(mid) { low = mid } else { high = mid }
        }
        return low
    }

    static func healthStatus(profile: FinancialProfile, date: Date) throws -> FinancialHealth {
        let headroom = try forecast(profile: profile, targetDate: date).safeToSpend
        if headroom < 0 { return .red }
        if headroom < profile.safetyBuffer { return .yellow }
        return .green
    }

    static func adherenceStatus(actualDiscretionarySpend: Double, recommendedBudget: Double, yellowTolerance: Double = 0.15) -> AdherenceStatus {
        guard recommendedBudget > 0 else { return actualDiscretionarySpend <= 0 ? .green : .red }
        let ratio = actualDiscretionarySpend / recommendedBudget
        if ratio <= 1.0 { return .green }
        if ratio <= 1.0 + max(0, yellowTolerance) { return .yellow }
        return .red
    }
}
