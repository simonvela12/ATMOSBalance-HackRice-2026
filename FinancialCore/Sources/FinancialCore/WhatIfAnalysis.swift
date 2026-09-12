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

public extension FinancialInsights {
    /// Evaluates a hypothetical purchase and then re-runs every goal with that purchase
    /// inserted into the cash path. This powers UI messages such as:
    /// “F1 is technically possible, but it moves Miami from SAFE to TIGHT.”
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
            // Spending now changes cash immediately; an event dated exactly at asOfDate
            // would otherwise be considered already reflected in currentCash.
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
                worsened: healthRank(after.status) > healthRank(before.status)
            )
        }

        return PurchaseWhatIfAnalysis(
            purchaseAssessment: purchase.assessment,
            purchaseExplanation: purchase.explanation,
            goalImpacts: impacts
        )
    }

    private static func healthRank(_ status: FinancialHealthStatus) -> Int {
        switch status {
        case .safe:
            return 0
        case .tight:
            return 1
        case .notSafe:
            return 2
        }
    }
}
