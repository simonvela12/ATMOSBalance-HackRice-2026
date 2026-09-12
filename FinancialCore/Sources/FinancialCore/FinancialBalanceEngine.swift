import Foundation

/// Provider-independent balance snapshot supplied by the banking ingestion layer.
/// `balance` is signed: assets are positive and liabilities (for example a credit
/// card balance owed) should be negative. `isLiquid` marks money that can actually
/// participate in today's cash planning.
public struct AccountBalanceSnapshot: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let balance: Double
    public let isLiquid: Bool

    public init(id: String, name: String, balance: Double, isLiquid: Bool) {
        self.id = id
        self.name = name
        self.balance = balance
        self.isLiquid = isLiquid
    }
}

/// A recommendation, not an automatic transfer. The engine never assumes that an
/// income transaction was contributed to a goal. `Goal.amountAlreadyPaid` remains
/// the source of truth for verified/declared goal progress; whenever that value is
/// lower than a previous plan expected, the next evaluation naturally increases
/// the required contribution because less time remains.
public struct ShortTermGoalContribution: Sendable, Equatable {
    public let goalID: UUID
    public let goalName: String
    public let deadline: Date
    public let priority: GoalPriority
    public let flexibility: GoalFlexibility
    public let recommendedContribution: Double
    public let requiredWeeklySavings: Double
    public let remainingAmount: Double
    public let status: GoalStatus
    public let alreadyProtectedInLiquidBalance: Bool
}

/// Separates what the user owns in aggregate from what is realistically usable.
///
/// `totalBalance` sums every supplied account snapshot, including signed liabilities.
/// `liquidAccountBalance` sums only liquid accounts.
/// `liquidBalanceBeforeGoalPlan` removes money that should not be touched: protected
/// reserves, the safety buffer, committed expenses, and mandatory goals due during
/// the short-term horizon.
/// `liquidBalanceAfterGoalPlan` additionally reserves the recommended contribution
/// for non-mandatory goals over the same horizon.
public struct FinancialBalanceSummary: Sendable {
    public let asOfDate: Date
    public let horizonEndDate: Date

    public let totalBalance: Double
    public let liquidAccountBalance: Double
    public let profileCurrentCash: Double
    public let profileCashDifference: Double

    public let currentPersonalReserve: Double
    public let currentInstitutionalMinimum: Double
    public let protectedReserveThroughHorizon: Double
    public let safetyBuffer: Double
    public let committedExpensesDue: Double
    public let mandatoryGoalPaymentsDue: Double

    public let liquidBalanceBeforeGoalPlan: Double
    public let shortTermGoalContributions: [ShortTermGoalContribution]
    public let shortTermGoalContributionTotal: Double
    public let additionalGoalContributionTotal: Double
    public let liquidBalanceAfterGoalPlan: Double
    public let spendableLiquidBalance: Double
    public let liquidShortfall: Double
}

public enum FinancialBalanceEngine {
    /// Builds the two-balance view used by the product UI.
    ///
    /// - Parameters:
    ///   - profile: Current normalized financial profile used by the forecasting engine.
    ///   - accountBalances: Latest normalized balances from Nessie/Plaid/etc. When empty,
    ///     `profile.currentCash` is used as a backward-compatible fallback for both balances.
    ///   - shortTermDays: Window used to protect near-term obligations and show recommended
    ///     goal contributions. Defaults to 30 days.
    public static func summarize(
        profile: FinancialProfile,
        accountBalances: [AccountBalanceSnapshot] = [],
        shortTermDays: Int = 30,
        calendar: Calendar = .current
    ) throws -> FinancialBalanceSummary {
        let horizonDays = max(0, shortTermDays)
        let horizonEnd = calendar.date(
            byAdding: .day,
            value: horizonDays,
            to: profile.asOfDate
        ) ?? profile.asOfDate

        let totalBalance: Double
        let liquidAccountBalance: Double
        if accountBalances.isEmpty {
            // Existing callers historically provide one normalized currentCash value.
            totalBalance = profile.currentCash
            liquidAccountBalance = profile.currentCash
        } else {
            totalBalance = accountBalances.reduce(0) { $0 + $1.balance }
            liquidAccountBalance = accountBalances
                .filter { $0.isLiquid }
                .reduce(0) { $0 + $1.balance }
        }

        let currentPersonalReserve = FinancialEngine.personalReserve(
            profile: profile,
            on: profile.asOfDate
        )
        let currentInstitutionalMinimum = FinancialEngine.institutionalMinimum(
            profile: profile,
            on: profile.asOfDate
        )
        let protectedReserve = maximumHardFloor(
            profile: profile,
            from: profile.asOfDate,
            through: horizonEnd,
            calendar: calendar
        )
        let buffer = FinancialEngine.safetyBuffer(profile: profile, calendar: calendar)
        let committedExpenses = FinancialEngine.committedExpenses(
            profile: profile,
            targetDate: horizonEnd
        )
        let mandatoryGoals = FinancialEngine.mandatoryGoalPayments(
            profile: profile,
            targetDate: horizonEnd
        )

        let beforeGoalPlan = liquidAccountBalance
            - protectedReserve
            - buffer
            - committedExpenses
            - mandatoryGoals

        let portfolio = try SmartGoalEngine.evaluate(
            profile: profile,
            planningHorizon: max(horizonEnd, profile.goals.map(\.deadline).max() ?? horizonEnd),
            calendar: calendar
        )

        let goalContributions = portfolio.goals.compactMap { health -> ShortTermGoalContribution? in
            guard health.goal.lifecycleState == .active,
                  !health.goal.isCompleted,
                  health.remainingAmount > 0.005 else {
                return nil
            }

            let contribution = recommendedContribution(
                for: health,
                horizonDays: horizonDays
            )
            let alreadyProtected = health.goal.priority == .mandatory
                && health.goal.deadline <= horizonEnd

            return ShortTermGoalContribution(
                goalID: health.goal.id,
                goalName: health.goal.name,
                deadline: health.goal.deadline,
                priority: health.goal.priority,
                flexibility: health.goal.flexibility,
                recommendedContribution: contribution,
                requiredWeeklySavings: health.requiredWeeklySavings,
                remainingAmount: health.remainingAmount,
                status: health.status,
                alreadyProtectedInLiquidBalance: alreadyProtected
            )
        }
        .sorted {
            if $0.deadline != $1.deadline { return $0.deadline < $1.deadline }
            return $0.goalName < $1.goalName
        }

        let contributionTotal = goalContributions.reduce(0) {
            $0 + $1.recommendedContribution
        }
        // Mandatory goals due inside the horizon were already removed above. Only
        // subtract the still-unreserved recommendations here to avoid double counting.
        let additionalGoalContributionTotal = goalContributions
            .filter { !$0.alreadyProtectedInLiquidBalance }
            .reduce(0) { $0 + $1.recommendedContribution }

        let afterGoalPlan = beforeGoalPlan - additionalGoalContributionTotal

        return FinancialBalanceSummary(
            asOfDate: profile.asOfDate,
            horizonEndDate: horizonEnd,
            totalBalance: totalBalance,
            liquidAccountBalance: liquidAccountBalance,
            profileCurrentCash: profile.currentCash,
            profileCashDifference: liquidAccountBalance - profile.currentCash,
            currentPersonalReserve: currentPersonalReserve,
            currentInstitutionalMinimum: currentInstitutionalMinimum,
            protectedReserveThroughHorizon: protectedReserve,
            safetyBuffer: buffer,
            committedExpensesDue: committedExpenses,
            mandatoryGoalPaymentsDue: mandatoryGoals,
            liquidBalanceBeforeGoalPlan: beforeGoalPlan,
            shortTermGoalContributions: goalContributions,
            shortTermGoalContributionTotal: contributionTotal,
            additionalGoalContributionTotal: additionalGoalContributionTotal,
            liquidBalanceAfterGoalPlan: afterGoalPlan,
            spendableLiquidBalance: max(0, afterGoalPlan),
            liquidShortfall: max(0, -afterGoalPlan)
        )
    }

    private static func recommendedContribution(
        for health: GoalHealth,
        horizonDays: Int
    ) -> Double {
        guard horizonDays > 0, health.remainingAmount > 0.005 else { return 0 }
        if health.daysRemaining <= 0 {
            return health.remainingAmount
        }
        let coveredDays = min(horizonDays, health.daysRemaining)
        return min(
            health.remainingAmount,
            health.requiredDailySavings * Double(coveredDays)
        )
    }

    private static func maximumHardFloor(
        profile: FinancialProfile,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar
    ) -> Double {
        guard endDate >= startDate else {
            return FinancialEngine.hardFloor(profile: profile, on: startDate)
        }

        var date = startDate
        var maximum = 0.0
        while date <= endDate {
            maximum = max(maximum, FinancialEngine.hardFloor(profile: profile, on: date))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else {
                break
            }
            date = next
        }
        return maximum
    }
}
