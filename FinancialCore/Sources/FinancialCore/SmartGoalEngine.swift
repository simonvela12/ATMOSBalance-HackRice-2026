import Foundation

public enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case ahead
    case onTrack
    case behind
    case atRisk
    case unrealistic
    case completed
    case paused
}

public struct GoalHealth: Sendable {
    public let goal: Goal
    public let progress: Double
    public let remainingAmount: Double
    public let daysRemaining: Int
    public let requiredDailySavings: Double
    public let requiredWeeklySavings: Double
    public let requiredMonthlySavings: Double
    public let projectedCompletionDate: Date?
    public let projectedAmountAtDeadline: Double
    public let daysAheadOrBehind: Int?
    public let shortfall: Double
    public let requiredAdditionalSavings: Double
    public let recommendedContribution: Double
    public let status: GoalStatus
    public let recommendedTargetDate: Date?
    public let protectionScore: Double
    public let allocatedFutureCash: Double
}

public struct GoalConflict: Sendable, Equatable {
    public let protectedGoalID: UUID
    public let constrainedGoalID: UUID
    public let amount: Double
}

public enum GoalPortfolioStatus: String, Sendable {
    case healthy
    case constrained
    case conflicted
    case noActiveGoals
}

public struct GoalPortfolioHealth: Sendable {
    public let status: GoalPortfolioStatus
    public let goals: [GoalHealth]
    public let allGoalsAchievable: Bool
    public let highestRiskGoalID: UUID?
    public let priorityGoalID: UUID?
    public let committedFutureCash: Double
    public let safeToSpendToday: Double
    public let requiredToSaveDaily: Double
    public let requiredToSaveWeekly: Double
    public let requiredToSaveMonthly: Double
    public let conflicts: [GoalConflict]
    public let recommendedGoalToDelayID: UUID?
}

/// A provider-independent movement used for impact analysis. Positive values are
/// income and negative values are spending. UI and banking adapters own the copy.
public struct GoalCashMovement: Sendable {
    public let amount: Double
    public let date: Date
    public let label: String

    public init(amount: Double, date: Date, label: String = "Cash movement") {
        self.amount = amount
        self.date = date
        self.label = label
    }
}

public struct GoalMovementImpact: Sendable {
    public let goal: Goal
    public let statusBefore: GoalStatus
    public let statusAfter: GoalStatus
    public let projectedCompletionDateChangeInDays: Int?
    public let shortfallChange: Double
    public let weeklySavingsChange: Double
}

public struct GoalTransactionImpact: Sendable {
    public let movement: GoalCashMovement
    public let safeToSpendChange: Double
    public let requiredToSaveWeeklyChange: Double
    public let goalImpacts: [GoalMovementImpact]
}

public enum SmartGoalEngine {
    /// Runs after the existing forecast and allocates its explainable cash capacity
    /// across goals. No result is persisted; a fresh profile always yields a fresh answer.
    public static func evaluate(
        profile: FinancialProfile,
        planningHorizon: Date? = nil,
        calendar: Calendar = .current
    ) throws -> GoalPortfolioHealth {
        let horizon = max(
            planningHorizon ?? profile.goals.map(\.deadline).max() ?? profile.asOfDate,
            profile.asOfDate
        )
        let ordered = profile.goals.sorted {
            let left = protectionScore(for: $0, asOf: profile.asOfDate, calendar: calendar)
            let right = protectionScore(for: $1, asOf: profile.asOfDate, calendar: calendar)
            if left != right { return left > right }
            if $0.deadline != $1.deadline { return $0.deadline < $1.deadline }
            return $0.id.uuidString < $1.id.uuidString
        }

        var fundingProfile = profile
        fundingProfile.goals = []
        var reservedForHigherPriority = 0.0
        var healthByID: [UUID: GoalHealth] = [:]

        for goal in ordered {
            let health = try evaluate(
                goal: goal,
                in: fundingProfile,
                reservedForHigherPriority: reservedForHigherPriority,
                planningHorizon: horizon,
                calendar: calendar
            )
            healthByID[goal.id] = health
            if goal.lifecycleState == .active {
                reservedForHigherPriority += health.allocatedFutureCash
            }
        }

        let health = profile.goals.compactMap { healthByID[$0.id] }
        let active = health.filter { ![.completed, .paused].contains($0.status) }
        let failing = active.filter { $0.shortfall > 0.005 }
        let protected = active.filter { $0.allocatedFutureCash > 0.005 }
        let maxDeadline = max(active.map { $0.goal.deadline }.max() ?? horizon, profile.asOfDate)

        var goalAwareProfile = fundingProfile
        goalAwareProfile.goals = protected.map { item in
            Goal(
                id: item.goal.id,
                name: item.goal.name,
                targetAmount: item.allocatedFutureCash,
                deadline: max(item.goal.deadline, profile.asOfDate),
                priority: .mandatory,
                flexibility: item.goal.flexibility
            )
        }
        let safeToSpend = try FinancialEngine.safeToSpend(
            profile: goalAwareProfile,
            from: profile.asOfDate,
            through: maxDeadline,
            calendar: calendar
        )

        let priorityGoal = ordered.first { $0.lifecycleState == .active && !$0.isCompleted }
        let riskGoal = failing.max {
            riskRank($0.status) == riskRank($1.status)
                ? $0.shortfall < $1.shortfall
                : riskRank($0.status) < riskRank($1.status)
        }
        let delayGoal = failing.max {
            let left = delaySuitability($0)
            let right = delaySuitability($1)
            return left == right ? $0.goal.deadline < $1.goal.deadline : left < right
        }

        let conflicts: [GoalConflict] = failing.compactMap { constrained in
            guard let protectedGoal = protected.first(where: {
                $0.goal.id != constrained.goal.id && $0.protectionScore > constrained.protectionScore
            }) else { return nil }
            return GoalConflict(
                protectedGoalID: protectedGoal.goal.id,
                constrainedGoalID: constrained.goal.id,
                amount: constrained.shortfall
            )
        }

        let portfolioStatus: GoalPortfolioStatus
        if active.isEmpty { portfolioStatus = .noActiveGoals }
        else if !conflicts.isEmpty { portfolioStatus = .conflicted }
        else if !failing.isEmpty { portfolioStatus = .constrained }
        else { portfolioStatus = .healthy }

        return GoalPortfolioHealth(
            status: portfolioStatus,
            goals: health,
            allGoalsAchievable: failing.isEmpty,
            highestRiskGoalID: riskGoal?.goal.id,
            priorityGoalID: priorityGoal?.id,
            committedFutureCash: active.reduce(0) { $0 + $1.allocatedFutureCash },
            safeToSpendToday: safeToSpend,
            requiredToSaveDaily: active.reduce(0) { $0 + $1.requiredDailySavings },
            requiredToSaveWeekly: active.reduce(0) { $0 + $1.requiredWeeklySavings },
            requiredToSaveMonthly: active.reduce(0) { $0 + $1.requiredMonthlySavings },
            conflicts: conflicts,
            recommendedGoalToDelayID: delayGoal?.goal.id
        )
    }

    public static func impact(
        of movement: GoalCashMovement,
        on profile: FinancialProfile,
        planningHorizon: Date? = nil,
        calendar: Calendar = .current
    ) throws -> GoalTransactionImpact {
        let before = try evaluate(profile: profile, planningHorizon: planningHorizon, calendar: calendar)
        var afterProfile = profile
        if movement.date <= profile.asOfDate {
            afterProfile.currentCash += movement.amount
        } else if movement.amount >= 0 {
            afterProfile.incomeEvents.append(IncomeEvent(
                amount: movement.amount,
                date: movement.date,
                source: movement.label,
                type: .oneTime
            ))
        } else {
            afterProfile.expenseEvents.append(ExpenseEvent(
                amount: abs(movement.amount),
                date: movement.date,
                category: movement.label,
                committed: true,
                extraordinary: true
            ))
        }
        let after = try evaluate(profile: afterProfile, planningHorizon: planningHorizon, calendar: calendar)
        let beforeByID = Dictionary(uniqueKeysWithValues: before.goals.map { ($0.goal.id, $0) })

        let impacts = after.goals.compactMap { updated -> GoalMovementImpact? in
            guard let original = beforeByID[updated.goal.id] else { return nil }
            let completionDelta: Int?
            if let old = original.projectedCompletionDate, let new = updated.projectedCompletionDate {
                completionDelta = calendar.dateComponents([.day], from: old, to: new).day
            } else {
                completionDelta = nil
            }
            return GoalMovementImpact(
                goal: updated.goal,
                statusBefore: original.status,
                statusAfter: updated.status,
                projectedCompletionDateChangeInDays: completionDelta,
                shortfallChange: updated.shortfall - original.shortfall,
                weeklySavingsChange: (updated.shortfall - original.shortfall)
                    / Double(max(1, updated.daysRemaining)) * 7
            )
        }

        return GoalTransactionImpact(
            movement: movement,
            safeToSpendChange: after.safeToSpendToday - before.safeToSpendToday,
            requiredToSaveWeeklyChange: after.requiredToSaveWeekly - before.requiredToSaveWeekly,
            goalImpacts: impacts
        )
    }

    public static func impact(
        of movements: [GoalCashMovement],
        on profile: FinancialProfile,
        planningHorizon: Date? = nil,
        calendar: Calendar = .current
    ) throws -> GoalTransactionImpact {
        let total = GoalCashMovement(
            amount: movements.reduce(0) { $0 + $1.amount },
            date: movements.map(\.date).max() ?? profile.asOfDate,
            label: "Daily activity"
        )
        return try impact(of: total, on: profile, planningHorizon: planningHorizon, calendar: calendar)
    }

    private static func evaluate(
        goal: Goal,
        in profile: FinancialProfile,
        reservedForHigherPriority: Double,
        planningHorizon: Date,
        calendar: Calendar
    ) throws -> GoalHealth {
        let progress = goal.targetAmount > 0
            ? min(1, max(0, goal.currentAmount / goal.targetAmount))
            : 1
        let remaining = goal.remainingAmount
        let rawDays = calendar.dateComponents([.day], from: profile.asOfDate, to: goal.deadline).day ?? 0
        let days = max(0, rawDays)
        let divisor = Double(max(1, days))
        let daily = remaining / divisor
        let monthly = daily * 30.4375
        let effectiveDeadline = max(goal.deadline, profile.asOfDate)
        let score = protectionScore(for: goal, asOf: profile.asOfDate, calendar: calendar)

        if goal.isCompleted {
            return GoalHealth(
                goal: goal, progress: 1, remainingAmount: 0, daysRemaining: days,
                requiredDailySavings: 0, requiredWeeklySavings: 0, requiredMonthlySavings: 0,
                projectedCompletionDate: profile.asOfDate, projectedAmountAtDeadline: goal.targetAmount,
                daysAheadOrBehind: max(0, rawDays), shortfall: 0, requiredAdditionalSavings: 0,
                recommendedContribution: 0, status: .completed, recommendedTargetDate: nil,
                protectionScore: score, allocatedFutureCash: 0
            )
        }
        if goal.lifecycleState == .paused {
            return GoalHealth(
                goal: goal, progress: progress, remainingAmount: remaining, daysRemaining: days,
                requiredDailySavings: 0, requiredWeeklySavings: 0, requiredMonthlySavings: 0,
                projectedCompletionDate: nil, projectedAmountAtDeadline: goal.currentAmount,
                daysAheadOrBehind: nil, shortfall: remaining, requiredAdditionalSavings: remaining,
                recommendedContribution: 0, status: .paused, recommendedTargetDate: nil,
                protectionScore: score, allocatedFutureCash: 0
            )
        }

        let deadlineForecast = try FinancialEngine.forecast(
            profile: profile,
            targetDate: effectiveDeadline,
            calendar: calendar
        )
        let available = max(0, deadlineForecast.recommendedHeadroom - reservedForHigherPriority)
        let allocation = min(remaining, available)
        let projectedAmount = min(goal.targetAmount, goal.currentAmount + allocation)
        let shortfall = max(0, goal.targetAmount - projectedAmount)
        let completion = try completionDate(
            remaining: remaining,
            profile: profile,
            reserved: reservedForHigherPriority,
            from: profile.asOfDate,
            through: alternativeHorizon(profile.asOfDate, planningHorizon, calendar),
            protectingThrough: effectiveDeadline,
            calendar: calendar
        )
        let delta = completion.flatMap {
            calendar.dateComponents([.day], from: $0, to: goal.deadline).day
        }

        let status: GoalStatus
        if rawDays < 0 { status = .unrealistic }
        else if shortfall <= 0.005 {
            status = (delta ?? 0) >= max(7, days / 10) ? .ahead : .onTrack
        } else {
            let ratio = shortfall / max(1, goal.targetAmount)
            if ratio <= 0.10 { status = .behind }
            else if ratio <= 0.30 { status = .atRisk }
            else { status = .unrealistic }
        }

        let recommendation: Date?
        if shortfall > 0.005 && goal.flexibility != .low {
            recommendation = completion ?? estimatedAlternativeDate(
                remaining: remaining,
                available: available,
                days: max(1, days),
                asOf: profile.asOfDate,
                calendar: calendar
            )
        } else {
            recommendation = nil
        }

        return GoalHealth(
            goal: goal,
            progress: progress,
            remainingAmount: remaining,
            daysRemaining: days,
            requiredDailySavings: daily,
            requiredWeeklySavings: daily * 7,
            requiredMonthlySavings: monthly,
            projectedCompletionDate: completion,
            projectedAmountAtDeadline: projectedAmount,
            daysAheadOrBehind: delta,
            shortfall: shortfall,
            requiredAdditionalSavings: shortfall,
            recommendedContribution: monthly,
            status: status,
            recommendedTargetDate: recommendation,
            protectionScore: score,
            allocatedFutureCash: allocation
        )
    }

    private static func completionDate(
        remaining: Double,
        profile: FinancialProfile,
        reserved: Double,
        from start: Date,
        through end: Date,
        protectingThrough deadline: Date,
        calendar: Calendar
    ) throws -> Date? {
        guard remaining > 0 else { return start }
        var candidates = [start]
        candidates.append(contentsOf: profile.incomeEvents.map(\.date))
        candidates.append(contentsOf: profile.personalReserveSteps.map(\.effectiveDate))
        candidates.append(contentsOf: profile.institutionalMinimums.compactMap { minimum in
            minimum.endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        })
        let candidateDays = Set(candidates.map { calendar.startOfDay(for: $0) })
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedDeadline = calendar.startOfDay(for: deadline)
        let normalizedEnd = calendar.startOfDay(for: end)

        // Precompute each candidate's lowest later headroom before the deadline in
        // one backward pass. This is materially cheaper than running a full daily
        // horizon scan again for every weekly or monthly income occurrence.
        var sustainableBeforeDeadline: [Date: Double] = [:]
        if normalizedDeadline > normalizedStart {
            var date = normalizedDeadline
            var suffixMinimum = Double.greatestFiniteMagnitude
            while date >= normalizedStart {
                let forecast = try FinancialEngine.forecast(profile: profile, targetDate: date, calendar: calendar)
                suffixMinimum = min(suffixMinimum, forecast.recommendedHeadroom)
                if candidateDays.contains(date) {
                    sustainableBeforeDeadline[date] = suffixMinimum
                }
                guard let previous = calendar.date(byAdding: .day, value: -1, to: date), previous < date else { break }
                date = previous
            }
        }

        for date in candidateDays.sorted() where date >= normalizedStart && date <= normalizedEnd {
            let forecast = try FinancialEngine.forecast(profile: profile, targetDate: date, calendar: calendar)
            let sustainableHeadroom: Double
            if date < normalizedDeadline {
                // Money is only genuinely available for a goal before its target date
                // when allocating it would not create a later cash shortage before the
                // deadline. This prevents a large current balance from producing a false
                // "funded today" ETA while rent or another obligation is about to land.
                sustainableHeadroom = min(
                    forecast.recommendedHeadroom,
                    sustainableBeforeDeadline[date] ?? forecast.recommendedHeadroom
                )
            } else {
                sustainableHeadroom = forecast.recommendedHeadroom
            }
            if sustainableHeadroom - reserved >= remaining { return date }
        }
        return nil
    }

    private static func alternativeHorizon(_ asOf: Date, _ horizon: Date, _ calendar: Calendar) -> Date {
        max(horizon, calendar.date(byAdding: .year, value: 5, to: asOf) ?? horizon)
    }

    private static func estimatedAlternativeDate(
        remaining: Double,
        available: Double,
        days: Int,
        asOf: Date,
        calendar: Calendar
    ) -> Date? {
        let dailyCapacity = available / Double(days)
        guard dailyCapacity > 0.005 else { return nil }
        return calendar.date(byAdding: .day, value: Int(ceil(remaining / dailyCapacity)), to: asOf)
    }

    private static func protectionScore(for goal: Goal, asOf: Date, calendar: Calendar) -> Double {
        let days = max(1, calendar.dateComponents([.day], from: asOf, to: goal.deadline).day ?? 1)
        let urgency = min(2, 30 / Double(days))
        let progress = goal.targetAmount > 0 ? min(1, goal.currentAmount / goal.targetAmount) : 1
        return goal.priority.weight * goal.flexibility.protectionWeight + urgency + progress * 0.25
    }

    private static func riskRank(_ status: GoalStatus) -> Int {
        switch status {
        case .unrealistic: 4
        case .atRisk: 3
        case .behind: 2
        case .onTrack, .ahead: 1
        case .paused, .completed: 0
        }
    }

    private static func delaySuitability(_ health: GoalHealth) -> Double {
        let flexibility: Double
        switch health.goal.flexibility {
        case .high: flexibility = 3
        case .medium: flexibility = 2
        case .low: flexibility = 0
        }
        return flexibility * 10 - health.goal.priority.weight + health.shortfall / max(1, health.goal.targetAmount)
    }
}
