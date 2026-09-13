import Foundation

public enum MaterialityPolicy {
    public static func recurringAmountDecision(
        expectedAmount: Double,
        actualAmount: Double,
        sameMerchant: Bool,
        riskBefore: PlanningRiskState,
        riskAfter: PlanningRiskState
    ) -> MaterialityDecision {
        guard sameMerchant else { return .askUser }
        guard riskBefore == riskAfter else { return .askUser }

        let expected = max(0, expectedAmount)
        let actual = max(0, actualAmount)
        let tolerance = max(3, expected * 0.01)
        return abs(actual - expected) <= tolerance ? .autoApply : .askUser
    }

    public static func plannedMatchDecision(
        plannedAmount: Double,
        actualAmount: Double,
        plannedDate: Date,
        actualDate: Date,
        dateWindow: DateWindow? = nil,
        strongIdentity: Bool,
        plausibleCandidateCount: Int = 1,
        riskBefore: PlanningRiskState,
        riskAfter: PlanningRiskState,
        calendar: Calendar = .current
    ) -> MaterialityDecision {
        guard strongIdentity else { return .askUser }
        guard plausibleCandidateCount == 1 else { return .askUser }
        guard riskBefore == riskAfter else { return .askUser }

        let planned = max(0, plannedAmount)
        let actual = max(0, actualAmount)
        let amountTolerance = max(5, planned * 0.02)
        guard abs(actual - planned) <= amountTolerance else { return .askUser }

        let withinWindow = dateWindow?.contains(actualDate) ?? false
        if withinWindow { return .autoApply }

        let plannedDay = calendar.startOfDay(for: plannedDate)
        let actualDay = calendar.startOfDay(for: actualDate)
        let dayDifference = abs(calendar.dateComponents([.day], from: plannedDay, to: actualDay).day ?? Int.max)
        return dayDifference <= 3 ? .autoApply : .askUser
    }
}

public extension MaterialityPolicy {
    /// Whether a recorded movement deserves the user's attention.
    ///
    /// The financial state is recalculated for every transaction regardless; this only
    /// decides whether anything is shown, so routine spending does not turn into a
    /// stream of notifications. Anything that moves the user between risk bands, moves a
    /// goal, or shortens the runway is always surfaced, however small the amount.
    static func transactionImpactDecision(
        amount: Double,
        safeToSpendBefore: Double,
        safeToSpendAfter: Double,
        riskBefore: PlanningRiskState,
        riskAfter: PlanningRiskState,
        goalScheduleChanged: Bool,
        runwayChanged: Bool
    ) -> MaterialityDecision {
        if riskBefore != riskAfter { return .askUser }
        if goalScheduleChanged || runwayChanged { return .askUser }

        // A couple of percent of what the user can spend, with a floor so small
        // balances do not make every purchase look dramatic.
        let tolerance = max(10, max(0, safeToSpendBefore) * 0.02)

        // Spending beyond what was safe to spend always deserves a word, even when the
        // headline number was already at zero and so cannot drop any further.
        if amount > max(0, safeToSpendBefore) + tolerance { return .askUser }

        let change = abs(safeToSpendAfter - safeToSpendBefore)
        return change <= tolerance ? .ignoreNoImpact : .askUser
    }
}
