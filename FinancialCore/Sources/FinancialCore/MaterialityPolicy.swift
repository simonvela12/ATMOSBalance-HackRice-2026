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
