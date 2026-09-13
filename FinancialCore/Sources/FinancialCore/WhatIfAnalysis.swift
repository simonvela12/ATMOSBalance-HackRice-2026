import Foundation

public struct GoalTradeoffImpact: Sendable {
    public let goal: Goal
    public let before: GoalPlanAssessment
    public let after: GoalPlanAssessment
    public let worsened: Bool
}

public struct PurchaseWhatIfAnalysis: Sendable {
    public let purchaseAssessment: PurchaseAssessment
    public let purchaseExplanation: PurchaseDecisionExplanation
    public let goalImpacts: [GoalTradeoffImpact]

    public var worsenedGoals: [GoalTradeoffImpact] {
        goalImpacts.filter(\.worsened)
    }
}

// MARK: - General What-If scenarios

/// The direction of one hypothetical cash-flow change.
public enum WhatIfCashFlowDirection: String, Codable, CaseIterable, Sendable {
    case income
    case expense
}

/// Recurrence supported by the What-If simulator. It intentionally mirrors the
/// product's scheduling vocabulary while remaining UI/provider independent.
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

    public init(
        every: Int = 1,
        unit: WhatIfRecurrenceUnit,
        endDate: Date? = nil,
        maxOccurrences: Int? = nil
    ) {
        self.every = max(1, every)
        self.unit = unit
        self.endDate = endDate
        self.maxOccurrences = maxOccurrences.map { max(1, $0) }
    }
}

/// One interpreted change in a scenario. A scenario can contain several changes,
/// for example a car down payment plus a monthly payment, or a new salary plus rent.
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

/// Structured scenario produced by UI controls or by an LLM parser. FinancialCore
/// never consumes free-form model output directly: only this validated structure.
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

/// The exact events inserted into the simulated profile. Exposing these makes the
/// result explainable and lets the UI show what the parser understood.
public struct WhatIfMaterializedMovement: Sendable {
    public let direction: WhatIfCashFlowDirection
    public let amount: Double
    public let date: Date
    public let label: String
}

/// Goal impact based on the richer SmartGoalEngine used by product-v1.4.
public struct WhatIfSmartGoalImpact: Sendable {
    public let goal: Goal
    public let statusBefore: GoalStatus
    public let statusAfter: GoalStatus
    public let projectedCompletionDateChangeInDays: Int?
    public let shortfallChange: Double
    public let weeklySavingsChange: Double

    public var worsened: Bool {
        shortfallChange > 0.005 ||
        (projectedCompletionDateChangeInDays ?? 0) > 0 ||
        Self.riskRank(statusAfter) > Self.riskRank(statusBefore)
    }

    private static func riskRank(_ status: GoalStatus) -> Int {
        switch status {
        case .ahead: return 0
        case .onTrack: return 1
        case .behind: return 2
        case .atRisk: return 3
        case .unrealistic: return 4
        case .paused: return 0
        case .completed: return 0
        }
    }
}

/// Shows how the same What-If behaves under the user's conservative, expected,
/// and optimistic financial profiles. The hypothetical event stays fixed; only the
/// uncertain parts of the user's existing financial profile move between scenarios.
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

    public var safeToSpendChange: Double {
        projected.safeToSpendNow - baseline.safeToSpendNow
    }

    public var weeklySpendingLimitChange: Double {
        projected.recommendedWeeklySpendingLimit - baseline.recommendedWeeklySpendingLimit
    }

    public var worsenedGoals: [GoalTradeoffImpact] {
        goalImpacts.filter(\.worsened)
    }

    public var worsenedSmartGoals: [WhatIfSmartGoalImpact] {
        smartGoalImpacts.filter(\.worsened)
    }
}

public extension FinancialInsights {
    /// Evaluates a free-form scenario after it has been converted to deterministic,
    /// structured cash-flow changes. Each recurrence is inserted on its real date;
    /// recurring spending is never collapsed into a fake lump-sum purchase.
    ///
    /// The baseline is the complete FinancialProfile: current cash, reserves,
    /// historical spending behavior, expected income, planned expenses and goals.
    /// This is the core rule that keeps What-If profile-aware rather than balance-only.
    static func analyzeWhatIfScenario(
        profile: FinancialProfile,
        scenario: WhatIfScenario,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> WhatIfScenarioAnalysis {
        guard planningHorizon >= profile.asOfDate else {
            throw FinancialEngineError.invalidDateRange
        }

        let baseline = try dashboard(
            profile: profile,
            through: planningHorizon,
            calendar: calendar
        )
        let beforeGoals = try assessAllGoals(
            profile: profile,
            planningHorizon: planningHorizon,
            calendar: calendar
        )
        let beforeSmart = try? SmartGoalEngine.evaluate(
            profile: profile,
            planningHorizon: planningHorizon,
            calendar: calendar
        )

        let applied = try applyWhatIfScenario(
            profile: profile,
            scenario: scenario,
            planningHorizon: planningHorizon,
            calendar: calendar
        )
        let afterProfile = applied.profile
        let movements = applied.movements

        let projected = try dashboard(
            profile: afterProfile,
            through: planningHorizon,
            calendar: calendar
        )
        let afterGoals = try assessAllGoals(
            profile: afterProfile,
            planningHorizon: planningHorizon,
            calendar: calendar
        )
        let afterSmart = try? SmartGoalEngine.evaluate(
            profile: afterProfile,
            planningHorizon: planningHorizon,
            calendar: calendar
        )

        let beforeByID = Dictionary(uniqueKeysWithValues: beforeGoals.map { ($0.goal.id, $0) })
        let goalImpacts = afterGoals.compactMap { after -> GoalTradeoffImpact? in
            guard let before = beforeByID[after.goal.id] else { return nil }
            return GoalTradeoffImpact(
                goal: after.goal,
                before: before,
                after: after,
                worsened: goalAssessmentWorsened(from: before, to: after)
            )
        }

        let smartImpacts = smartGoalImpacts(
            before: beforeSmart,
            after: afterSmart,
            calendar: calendar
        )

        let uncertainty = try FinancialScenario.allCases.map { financialScenario in
            let beforeProfile = FinancialScenarioEngine.adjustedProfile(
                profile,
                for: financialScenario,
                calendar: calendar
            )
            let afterScenarioProfile = FinancialScenarioEngine.adjustedProfile(
                afterProfile,
                for: financialScenario,
                calendar: calendar
            )
            let beforeDashboard = try dashboard(
                profile: beforeProfile,
                through: planningHorizon,
                calendar: calendar
            )
            let afterDashboard = try dashboard(
                profile: afterScenarioProfile,
                through: planningHorizon,
                calendar: calendar
            )
            return WhatIfScenarioOutcome(
                financialScenario: financialScenario,
                beforeStatus: beforeDashboard.horizonStatus,
                afterStatus: afterDashboard.horizonStatus,
                safeToSpendBefore: beforeDashboard.safeToSpendNow,
                safeToSpendAfter: afterDashboard.safeToSpendNow,
                minimumRecommendedHeadroomBefore: beforeDashboard.minimumRecommendedHeadroom,
                minimumRecommendedHeadroomAfter: afterDashboard.minimumRecommendedHeadroom
            )
        }

        return WhatIfScenarioAnalysis(
            scenario: scenario,
            baseline: baseline,
            projected: projected,
            goalImpacts: goalImpacts,
            smartGoalImpacts: smartImpacts,
            scenarioOutcomes: uncertainty,
            movements: movements,
            totalIncome: movements
                .filter { $0.direction == .income }
                .reduce(0) { $0 + $1.amount },
            totalExpenses: movements
                .filter { $0.direction == .expense }
                .reduce(0) { $0 + $1.amount }
        )
    }

    /// Applies a structured What-If to a copy of the profile. This function is public
    /// so tests and future charting surfaces can inspect the exact simulated cash path.
    static func applyWhatIfScenario(
        profile: FinancialProfile,
        scenario: WhatIfScenario,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> (profile: FinancialProfile, movements: [WhatIfMaterializedMovement]) {
        guard planningHorizon >= profile.asOfDate else {
            throw FinancialEngineError.invalidDateRange
        }

        var simulated = profile
        var movements: [WhatIfMaterializedMovement] = []

        for change in scenario.changes {
            guard change.amount >= 0 else { throw FinancialEngineError.negativeAmount }
            guard change.amount > 0 else { continue }

            for date in whatIfOccurrenceDates(
                for: change,
                asOfDate: profile.asOfDate,
                planningHorizon: planningHorizon,
                calendar: calendar
            ) {
                let movement = WhatIfMaterializedMovement(
                    direction: change.direction,
                    amount: change.amount,
                    date: date,
                    label: change.label
                )
                movements.append(movement)

                if date <= profile.asOfDate {
                    simulated.currentCash += change.direction == .income ? change.amount : -change.amount
                    continue
                }

                switch change.direction {
                case .income:
                    simulated.incomeEvents.append(
                        IncomeEvent(
                            amount: change.amount,
                            date: date,
                            source: change.label,
                            type: change.confidence < 0.999 ? .irregular : .oneTime,
                            confidence: change.confidence,
                            planningSource: .planned,
                            planningStatus: .planned
                        )
                    )
                case .expense:
                    simulated.expenseEvents.append(
                        ExpenseEvent(
                            amount: change.amount,
                            date: date,
                            category: change.label,
                            essential: change.essential,
                            committed: true,
                            reimbursable: false,
                            extraordinary: true,
                            planningSource: .planned,
                            planningStatus: .planned
                        )
                    )
                }
            }
        }

        movements.sort { $0.date == $1.date ? $0.label < $1.label : $0.date < $1.date }
        return (simulated, movements)
    }

    /// Evaluates a hypothetical purchase and then re-runs every goal with that purchase
    /// inserted into the cash path. Kept for backwards compatibility with the original UI.
    static func analyzePurchaseWhatIf(
        profile: FinancialProfile,
        amount: Double,
        purchaseDate: Date,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> PurchaseWhatIfAnalysis {
        let purchase = try assessAndExplainPurchase(
            profile: profile,
            amount: amount,
            purchaseDate: purchaseDate,
            planningHorizon: planningHorizon,
            calendar: calendar
        )

        let beforeGoals = try assessAllGoals(
            profile: profile,
            planningHorizon: planningHorizon,
            calendar: calendar
        )
        let beforeByID = Dictionary(uniqueKeysWithValues: beforeGoals.map { ($0.goal.id, $0) })

        var afterProfile = profile
        if purchaseDate == profile.asOfDate {
            afterProfile.currentCash -= amount
        } else {
            afterProfile.expenseEvents.append(
                ExpenseEvent(
                    amount: amount,
                    date: purchaseDate,
                    category: "What-If purchase",
                    essential: false,
                    committed: true,
                    reimbursable: false,
                    extraordinary: true
                )
            )
        }

        let afterGoals = try assessAllGoals(
            profile: afterProfile,
            planningHorizon: planningHorizon,
            calendar: calendar
        )

        let impacts: [GoalTradeoffImpact] = afterGoals.compactMap { after in
            guard let before = beforeByID[after.goal.id] else { return nil }
            return GoalTradeoffImpact(
                goal: after.goal,
                before: before,
                after: after,
                worsened: goalAssessmentWorsened(from: before, to: after)
            )
        }

        return PurchaseWhatIfAnalysis(
            purchaseAssessment: purchase.assessment,
            purchaseExplanation: purchase.explanation,
            goalImpacts: impacts
        )
    }

    private static func whatIfOccurrenceDates(
        for change: WhatIfCashFlowChange,
        asOfDate: Date,
        planningHorizon: Date,
        calendar: Calendar
    ) -> [Date] {
        let first = calendar.startOfDay(for: change.startDate)
        let asOf = calendar.startOfDay(for: asOfDate)
        let horizon = calendar.startOfDay(for: planningHorizon)

        guard first <= horizon else { return [] }
        guard let recurrence = change.recurrence else {
            return first >= asOf ? [first] : []
        }

        let explicitEnd = recurrence.endDate.map { calendar.startOfDay(for: $0) }
        let end = min(explicitEnd ?? horizon, horizon)
        let maximum = min(recurrence.maxOccurrences ?? 240, 240)
        var result: [Date] = []
        var current = first
        var generated = 0

        while current <= end && generated < maximum {
            if current >= asOf { result.append(current) }
            generated += 1

            let next: Date?
            switch recurrence.unit {
            case .day:
                next = calendar.date(byAdding: .day, value: recurrence.every, to: current)
            case .week:
                next = calendar.date(byAdding: .day, value: recurrence.every * 7, to: current)
            case .month:
                next = calendar.date(byAdding: .month, value: recurrence.every, to: current)
            case .year:
                next = calendar.date(byAdding: .year, value: recurrence.every, to: current)
            }
            guard let next, next > current else { break }
            current = next
        }

        return result
    }

    private static func smartGoalImpacts(
        before: GoalPortfolioHealth?,
        after: GoalPortfolioHealth?,
        calendar: Calendar
    ) -> [WhatIfSmartGoalImpact] {
        guard let before, let after else { return [] }
        let beforeByID = Dictionary(uniqueKeysWithValues: before.goals.map { ($0.goal.id, $0) })

        return after.goals.compactMap { updated in
            guard let original = beforeByID[updated.goal.id] else { return nil }
            let completionDelta: Int?
            if let old = original.projectedCompletionDate, let new = updated.projectedCompletionDate {
                completionDelta = calendar.dateComponents([.day], from: old, to: new).day
            } else if original.projectedCompletionDate != nil && updated.projectedCompletionDate == nil {
                completionDelta = Int.max
            } else {
                completionDelta = nil
            }

            return WhatIfSmartGoalImpact(
                goal: updated.goal,
                statusBefore: original.status,
                statusAfter: updated.status,
                projectedCompletionDateChangeInDays: completionDelta,
                shortfallChange: updated.shortfall - original.shortfall,
                weeklySavingsChange: updated.requiredWeeklySavings - original.requiredWeeklySavings
            )
        }
    }

    private static func goalAssessmentWorsened(
        from before: GoalPlanAssessment,
        to after: GoalPlanAssessment
    ) -> Bool {
        let beforeRank = healthRank(before.status)
        let afterRank = healthRank(after.status)

        if afterRank != beforeRank {
            return afterRank > beforeRank
        }

        let tolerance = 0.005
        if after.shortfallToHardFloor > before.shortfallToHardFloor + tolerance {
            return true
        }
        if after.shortfallToRecommendedFloor > before.shortfallToRecommendedFloor + tolerance {
            return true
        }
        return false
    }

    private static func healthRank(_ status: FinancialHealthStatus) -> Int {
        switch status {
        case .safe: return 0
        case .tight: return 1
        case .notSafe: return 2
        }
    }
}
