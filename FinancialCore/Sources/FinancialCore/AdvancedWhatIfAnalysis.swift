import Foundation

public enum WhatIfCashFlowDirection: String, Codable, CaseIterable, Sendable {
    case income
    case expense
}

public enum WhatIfRecurrenceUnit: String, Codable, CaseIterable, Sendable {
    case day
    case week
    case month
    case year
}

public struct WhatIfRecurrence: Codable, Equatable, Sendable {
    public let every: Int
    public let unit: WhatIfRecurrenceUnit
    public let endDate: Date?
    public let maxOccurrences: Int?

    public init(every: Int = 1, unit: WhatIfRecurrenceUnit, endDate: Date? = nil, maxOccurrences: Int? = nil) {
        self.every = max(1, every)
        self.unit = unit
        self.endDate = endDate
        self.maxOccurrences = maxOccurrences.map { max(1, $0) }
    }
}

public struct WhatIfCashFlowChange: Codable, Identifiable, Sendable {
    public let id: UUID
    public let direction: WhatIfCashFlowDirection
    public let amount: Double
    public let startDate: Date
    public let recurrence: WhatIfRecurrence?
    public let label: String
    public let essential: Bool
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        direction: WhatIfCashFlowDirection,
        amount: Double,
        startDate: Date,
        recurrence: WhatIfRecurrence? = nil,
        label: String,
        essential: Bool = false,
        confidence: Double = 1
    ) {
        self.id = id
        self.direction = direction
        self.amount = max(0, amount)
        self.startDate = startDate
        self.recurrence = recurrence
        self.label = label
        self.essential = essential
        self.confidence = min(max(confidence, 0), 1)
    }
}

/// Validated output of an intent interpreter. FinancialCore accepts this structure,
/// never free-form model prose.
public struct WhatIfScenario: Codable, Sendable {
    public let title: String
    public let sourceText: String?
    public let changes: [WhatIfCashFlowChange]

    public init(title: String, sourceText: String? = nil, changes: [WhatIfCashFlowChange]) {
        self.title = title
        self.sourceText = sourceText
        self.changes = changes
    }
}

public struct WhatIfMaterializedMovement: Sendable {
    public let direction: WhatIfCashFlowDirection
    public let amount: Double
    public let date: Date
    public let label: String
}

public struct WhatIfSmartGoalImpact: Sendable {
    public let goal: Goal
    public let statusBefore: GoalStatus
    public let statusAfter: GoalStatus
    public let projectedCompletionDateChangeInDays: Int?
    public let projectedCompletionDateBefore: Date?
    public let projectedCompletionDateAfter: Date?
    public let projectedAmountAtDeadlineBefore: Double
    public let projectedAmountAtDeadlineAfter: Double
    public let shortfallBefore: Double
    public let shortfallAfter: Double
    public let shortfallChange: Double
    public let additionalWeeklySavingsBefore: Double
    public let additionalWeeklySavingsAfter: Double
    public let weeklySavingsChange: Double

    public var worsened: Bool {
        shortfallChange > 0.005 ||
        (projectedCompletionDateChangeInDays ?? 0) > 0 ||
        Self.rank(statusAfter) > Self.rank(statusBefore)
    }

    private static func rank(_ status: GoalStatus) -> Int {
        switch status {
        case .ahead: return 0
        case .onTrack: return 1
        case .behind: return 2
        case .atRisk: return 3
        case .unrealistic: return 4
        case .paused, .completed: return 0
        }
    }
}

public struct WhatIfScenarioOutcome: Sendable {
    public let financialScenario: FinancialScenario
    public let beforeStatus: FinancialHealthStatus
    public let afterStatus: FinancialHealthStatus
    public let safeToSpendBefore: Double
    public let safeToSpendAfter: Double
    public let minimumRecommendedHeadroomBefore: Double
    public let minimumRecommendedHeadroomAfter: Double
}

public struct WhatIfScenarioAnalysis: Sendable {
    public let scenario: WhatIfScenario
    public let baseline: FinancialDashboardSnapshot
    public let projected: FinancialDashboardSnapshot
    public let goalImpacts: [GoalTradeoffImpact]
    public let smartGoalImpacts: [WhatIfSmartGoalImpact]
    public let scenarioOutcomes: [WhatIfScenarioOutcome]
    public let movements: [WhatIfMaterializedMovement]
    public let totalIncome: Double
    public let totalExpenses: Double

    public var safeToSpendChange: Double { projected.safeToSpendNow - baseline.safeToSpendNow }
    public var weeklySpendingLimitChange: Double { projected.recommendedWeeklySpendingLimit - baseline.recommendedWeeklySpendingLimit }
    public var worsenedSmartGoals: [WhatIfSmartGoalImpact] { smartGoalImpacts.filter(\.worsened) }
}

public extension FinancialInsights {
    static func analyzeWhatIfScenario(
        profile: FinancialProfile,
        scenario: WhatIfScenario,
        planningHorizon: Date,
        availableToSpendNow: Double? = nil,
        calendar: Calendar = .current
    ) throws -> WhatIfScenarioAnalysis {
        guard planningHorizon >= profile.asOfDate else { throw FinancialEngineError.invalidDateRange }

        let rawBaseline = try dashboard(profile: profile, through: planningHorizon, calendar: calendar)
        let beforeGoals = try assessAllGoals(profile: profile, planningHorizon: planningHorizon, calendar: calendar)
        let beforeSmart = try? SmartGoalEngine.evaluate(profile: profile, planningHorizon: planningHorizon, calendar: calendar)
        let applied = try applyWhatIfScenario(profile: profile, scenario: scenario, planningHorizon: planningHorizon, calendar: calendar)
        let rawProjected = try dashboard(profile: applied.profile, through: planningHorizon, calendar: calendar)
        let baselineLimit = availableToSpendNow.map { min(max(0, $0), max(0, profile.currentCash)) }
        let baseline = contextualDashboard(rawBaseline, replacingSafeToSpendWith: baselineLimit)
        let projectedLimit = baselineLimit.map {
            max(0, $0 + rawProjected.minimumRecommendedHeadroom - rawBaseline.minimumRecommendedHeadroom)
        }
        let projected = contextualDashboard(rawProjected, replacingSafeToSpendWith: projectedLimit)
        let afterGoals = try assessAllGoals(profile: applied.profile, planningHorizon: planningHorizon, calendar: calendar)
        let afterSmart = try? SmartGoalEngine.evaluate(profile: applied.profile, planningHorizon: planningHorizon, calendar: calendar)

        let beforeByID = Dictionary(uniqueKeysWithValues: beforeGoals.map { ($0.goal.id, $0) })
        let goalImpacts = afterGoals.compactMap { after -> GoalTradeoffImpact? in
            guard let before = beforeByID[after.goal.id] else { return nil }
            return GoalTradeoffImpact(
                goal: after.goal,
                before: before,
                after: after,
                worsened: advancedGoalWorsened(before: before, after: after)
            )
        }

        let outcomes = try FinancialScenario.allCases.map { financialScenario in
            let beforeProfile = FinancialScenarioEngine.adjustedProfile(profile, for: financialScenario, calendar: calendar)
            let afterProfile = FinancialScenarioEngine.adjustedProfile(applied.profile, for: financialScenario, calendar: calendar)
            let before = try dashboard(profile: beforeProfile, through: planningHorizon, calendar: calendar)
            let after = try dashboard(profile: afterProfile, through: planningHorizon, calendar: calendar)
            let scenarioBeforeLimit = baselineLimit.map {
                max(0, $0 + before.minimumRecommendedHeadroom - rawBaseline.minimumRecommendedHeadroom)
            } ?? before.safeToSpendNow
            let scenarioAfterLimit = max(
                0,
                scenarioBeforeLimit + after.minimumRecommendedHeadroom - before.minimumRecommendedHeadroom
            )
            return WhatIfScenarioOutcome(
                financialScenario: financialScenario,
                beforeStatus: before.horizonStatus,
                afterStatus: after.horizonStatus,
                safeToSpendBefore: scenarioBeforeLimit,
                safeToSpendAfter: scenarioAfterLimit,
                minimumRecommendedHeadroomBefore: before.minimumRecommendedHeadroom,
                minimumRecommendedHeadroomAfter: after.minimumRecommendedHeadroom
            )
        }

        return WhatIfScenarioAnalysis(
            scenario: scenario,
            baseline: baseline,
            projected: projected,
            goalImpacts: goalImpacts,
            smartGoalImpacts: advancedSmartGoalImpacts(before: beforeSmart, after: afterSmart, calendar: calendar),
            scenarioOutcomes: outcomes,
            movements: applied.movements,
            totalIncome: applied.movements.filter { $0.direction == .income }.reduce(0) { $0 + $1.amount },
            totalExpenses: applied.movements.filter { $0.direction == .expense }.reduce(0) { $0 + $1.amount }
        )
    }

    static func applyWhatIfScenario(
        profile: FinancialProfile,
        scenario: WhatIfScenario,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> (profile: FinancialProfile, movements: [WhatIfMaterializedMovement]) {
        guard planningHorizon >= profile.asOfDate else { throw FinancialEngineError.invalidDateRange }
        var simulated = profile
        var movements: [WhatIfMaterializedMovement] = []

        for change in scenario.changes where change.amount > 0 {
            for date in advancedOccurrenceDates(for: change, asOfDate: profile.asOfDate, planningHorizon: planningHorizon, calendar: calendar) {
                movements.append(.init(direction: change.direction, amount: change.amount, date: date, label: change.label))
                if date <= profile.asOfDate {
                    simulated.currentCash += change.direction == .income ? change.amount : -change.amount
                } else if change.direction == .income {
                    simulated.incomeEvents.append(IncomeEvent(
                        amount: change.amount,
                        date: date,
                        source: change.label,
                        type: change.confidence < 0.999 ? .irregular : .oneTime,
                        confidence: change.confidence,
                        planningSource: .planned,
                        planningStatus: .planned
                    ))
                } else {
                    simulated.expenseEvents.append(ExpenseEvent(
                        amount: change.amount,
                        date: date,
                        category: change.label,
                        essential: change.essential,
                        committed: true,
                        reimbursable: false,
                        extraordinary: true,
                        planningSource: .planned,
                        planningStatus: .planned
                    ))
                }
            }
        }
        movements.sort { $0.date == $1.date ? $0.label < $1.label : $0.date < $1.date }
        return (simulated, movements)
    }
}

private func contextualDashboard(
    _ source: FinancialDashboardSnapshot,
    replacingSafeToSpendWith replacement: Double?
) -> FinancialDashboardSnapshot {
    guard let replacement else { return source }
    return FinancialDashboardSnapshot(
        asOfDate: source.asOfDate,
        planningHorizon: source.planningHorizon,
        currentStatus: source.currentStatus,
        horizonStatus: source.horizonStatus,
        safeToSpendNow: max(0, replacement),
        typicalWeeklySpending: source.typicalWeeklySpending,
        additionalWeeklyCapacity: source.additionalWeeklyCapacity,
        recommendedWeeklySpendingLimit: source.recommendedWeeklySpendingLimit,
        minimumHardHeadroom: source.minimumHardHeadroom,
        minimumRecommendedHeadroom: source.minimumRecommendedHeadroom,
        tightestDate: source.tightestDate
    )
}

private func advancedOccurrenceDates(
    for change: WhatIfCashFlowChange,
    asOfDate: Date,
    planningHorizon: Date,
    calendar: Calendar
) -> [Date] {
    let first = calendar.startOfDay(for: change.startDate)
    let asOf = calendar.startOfDay(for: asOfDate)
    let horizon = calendar.startOfDay(for: planningHorizon)
    guard first <= horizon else { return [] }
    guard let recurrence = change.recurrence else { return first >= asOf ? [first] : [] }

    let end = min(recurrence.endDate.map { calendar.startOfDay(for: $0) } ?? horizon, horizon)
    let maximum = min(recurrence.maxOccurrences ?? 240, 240)
    var dates: [Date] = []
    var current = first
    while current <= end && dates.count < maximum {
        if current >= asOf { dates.append(current) }
        let next: Date?
        switch recurrence.unit {
        case .day: next = calendar.date(byAdding: .day, value: recurrence.every, to: current)
        case .week: next = calendar.date(byAdding: .day, value: recurrence.every * 7, to: current)
        case .month: next = calendar.date(byAdding: .month, value: recurrence.every, to: current)
        case .year: next = calendar.date(byAdding: .year, value: recurrence.every, to: current)
        }
        guard let next, next > current else { break }
        current = next
    }
    return dates
}

private func advancedGoalWorsened(before: GoalPlanAssessment, after: GoalPlanAssessment) -> Bool {
    func rank(_ status: FinancialHealthStatus) -> Int {
        switch status { case .safe: return 0; case .tight: return 1; case .notSafe: return 2 }
    }
    return rank(after.status) > rank(before.status) ||
        after.shortfallToHardFloor > before.shortfallToHardFloor + 0.005 ||
        after.shortfallToRecommendedFloor > before.shortfallToRecommendedFloor + 0.005
}

private func advancedSmartGoalImpacts(
    before: GoalPortfolioHealth?,
    after: GoalPortfolioHealth?,
    calendar: Calendar
) -> [WhatIfSmartGoalImpact] {
    guard let before, let after else { return [] }
    let prior = Dictionary(uniqueKeysWithValues: before.goals.map { ($0.goal.id, $0) })
    return after.goals.compactMap { updated in
        guard let original = prior[updated.goal.id] else { return nil }
        let days: Int?
        if let old = original.projectedCompletionDate, let new = updated.projectedCompletionDate {
            days = calendar.dateComponents([.day], from: old, to: new).day
        } else if original.projectedCompletionDate != nil && updated.projectedCompletionDate == nil {
            days = Int.max
        } else { days = nil }
        return WhatIfSmartGoalImpact(
            goal: updated.goal,
            statusBefore: original.status,
            statusAfter: updated.status,
            projectedCompletionDateChangeInDays: days,
            projectedCompletionDateBefore: original.projectedCompletionDate,
            projectedCompletionDateAfter: updated.projectedCompletionDate,
            projectedAmountAtDeadlineBefore: original.projectedAmountAtDeadline,
            projectedAmountAtDeadlineAfter: updated.projectedAmountAtDeadline,
            shortfallBefore: original.shortfall,
            shortfallAfter: updated.shortfall,
            shortfallChange: updated.shortfall - original.shortfall,
            additionalWeeklySavingsBefore: original.shortfall / Double(max(1, original.daysRemaining)) * 7,
            additionalWeeklySavingsAfter: updated.shortfall / Double(max(1, updated.daysRemaining)) * 7,
            weeklySavingsChange: (
                updated.shortfall / Double(max(1, updated.daysRemaining)) * 7
            ) - (
                original.shortfall / Double(max(1, original.daysRemaining)) * 7
            )
        )
    }
}
