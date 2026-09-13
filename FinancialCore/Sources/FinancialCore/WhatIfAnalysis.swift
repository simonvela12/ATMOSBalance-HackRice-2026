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
    ///
    /// A goal is also considered worsened when it remains in the same health band but
    /// develops a larger funding shortfall. This prevents the UI from saying that a goal
    /// was unaffected merely because both the before and after states are TIGHT (or both
    /// are NOT_SAFE).
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
                worsened: goalAssessmentWorsened(from: before, to: after)
            )
        }

        return PurchaseWhatIfAnalysis(
            purchaseAssessment: purchase.assessment,
            purchaseExplanation: purchase.explanation,
            goalImpacts: impacts
        )
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

        // Dollar values come from deterministic arithmetic, but using a small tolerance
        // avoids classifying floating-point noise as a real change in the user's plan.
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
        case .safe:
            return 0
        case .tight:
            return 1
        case .notSafe:
            return 2
        }
    }
}

