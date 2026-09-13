import Foundation

public enum MaterialityPolicy {
    public static func recurringAmountDecision(expectedAmount: Double, actualAmount: Double, sameMerchant: Bool, riskBefore: PlanningRiskState, riskAfter: PlanningRiskState) -> MaterialityDecision {
        guard sameMerchant, riskBefore == riskAfter else { return .askUser }
        let expected = max(0, expectedAmount), actual = max(0, actualAmount)
        return abs(actual - expected) <= max(3, expected * 0.01) ? .autoApply : .askUser
    }

    public static func plannedMatchDecision(plannedAmount: Double, actualAmount: Double, plannedDate: Date, actualDate: Date, dateWindow: DateWindow? = nil, strongIdentity: Bool, plausibleCandidateCount: Int = 1, riskBefore: PlanningRiskState, riskAfter: PlanningRiskState, calendar: Calendar = .current) -> MaterialityDecision {
        guard strongIdentity, plausibleCandidateCount == 1, riskBefore == riskAfter else { return .askUser }
        let planned = max(0, plannedAmount), actual = max(0, actualAmount)
        guard abs(actual - planned) <= max(5, planned * 0.02) else { return .askUser }
        if dateWindow?.contains(actualDate) == true { return .autoApply }
        let difference = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: plannedDate), to: calendar.startOfDay(for: actualDate)).day ?? .max)
        return difference <= 3 ? .autoApply : .askUser
    }
}
