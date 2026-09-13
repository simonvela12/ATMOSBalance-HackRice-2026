import Foundation

public struct GoalTradeoffImpact: Sendable {
    public let goal: Goal
    public let before: GoalPlanAssessment
    public let after: GoalPlanAssessment
    public let worsened: Bool
}

/// The verdict the product shows. Derived from the conservative scenario, because that
/// is the recommendation the user is given by default.
public enum PurchaseRecommendation: String, Codable, Sendable {
    case recommended
    case possibleButTight
    case notRecommended
}

/// One scenario's view of the same purchase.
public struct ScenarioPurchaseOutcome: Sendable {
    public let scenario: FinancialScenario
    public let safeToSpendBefore: Double
    public let safeToSpendAfter: Double
    public let status: FinancialHealthStatus
    public let runwaySatisfied: Bool
    public let limitingConstraint: FinancialConstraint?
}

/// The full consequences of a hypothetical purchase, not merely whether it fits.
///
/// Every number here comes from the same engine that produces the live figures, so a
/// What-If can never disagree with the home screen.
public struct PurchaseWhatIfAnalysis: Sendable {
    public let purchaseAssessment: PurchaseAssessment
    public let purchaseExplanation: PurchaseDecisionExplanation
    public let goalImpacts: [GoalTradeoffImpact]

    public let safeToSpendBefore: ScenarioSafeToSpend
    public let safeToSpendAfter: ScenarioSafeToSpend
    public let runwayBefore: RunwayAssessment
    public let runwayAfter: RunwayAssessment
    /// How each goal's expected date moves because of this purchase.
    public let goalDateChanges: [GoalDateChange]
    public let scenarioOutcomes: [ScenarioPurchaseOutcome]
    public let limitingConstraint: FinancialConstraint?
    /// Future money this purchase would depend on that is not certain to arrive.
    public let dependsOnUncertainIncome: [IncomeDependency]
    public let recommendation: PurchaseRecommendation

    public var worsenedGoals: [GoalTradeoffImpact] {
        goalImpacts.filter(\.worsened)
    }

    /// Goals whose date actually moves, which is what the user cares about seeing.
    public var movedGoals: [GoalDateChange] {
        goalDateChanges.filter(\.moved)
    }

    /// The shortfall to make up if the purchase is not affordable, else zero.
    public var shortfall: Double {
        purchaseAssessment.shortfallToHardFloor
    }

    /// How many days sooner the money would run out. Negative means sooner.
    public func runwayShiftInDays(calendar: Calendar = .current) -> Int? {
        FinancialStateEngine.runwayShiftInDays(
            from: runwayBefore,
            to: runwayAfter,
            calendar: calendar
        )
    }
}

public extension FinancialInsights {
    /// Evaluates a hypothetical purchase against the whole plan: the headline number in
    /// all three scenarios, the user's runway, every goal's date, and the single
    /// constraint that binds.
    ///
    /// A goal is considered worsened when it changes health band *or* develops a larger
    /// funding shortfall, so the UI never claims a goal was unaffected merely because
    /// both the before and after states are TIGHT.
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

        // Spending now changes the balance immediately; anything dated later becomes a
        // committed event. `applying` is the same mutation the state engine uses, so a
        // What-If is exactly "what the app would show if this had happened".
        let afterProfile = profile.applying(
            RecordedTransaction(
                amount: -amount,
                date: purchaseDate,
                label: "What-If purchase",
                category: "What-If purchase"
            )
        )

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

        let before = try SafeToSpendEngine.evaluateAllScenarios(
            profile: profile,
            calendar: calendar
        )
        let after = try SafeToSpendEngine.evaluateAllScenarios(
            profile: afterProfile,
            calendar: calendar
        )

        let outcomes = FinancialScenario.allCases.map { scenario -> ScenarioPurchaseOutcome in
            let start = before.result(for: scenario)
            let end = after.result(for: scenario)
            return ScenarioPurchaseOutcome(
                scenario: scenario,
                safeToSpendBefore: start.amount,
                safeToSpendAfter: end.amount,
                status: end.status,
                runwaySatisfied: end.runway.isSatisfied,
                limitingConstraint: end.limitingConstraint
            )
        }

        let conservativeAfter = after.primary
        // The conservative answer never counts uncertain money, so it has no
        // dependencies of its own. When a purchase only works under the less cautious
        // assumptions, the money it is betting on is what the user needs to be told
        // about.
        let dependencies = conservativeAfter.dependsOnUncertainIncome.isEmpty
            ? after.expected.dependsOnUncertainIncome
            : conservativeAfter.dependsOnUncertainIncome

        let recommendation: PurchaseRecommendation
        if conservativeAfter.status == .notSafe || !conservativeAfter.runway.isSatisfied {
            recommendation = .notRecommended
        } else if conservativeAfter.status == .tight {
            recommendation = .possibleButTight
        } else {
            recommendation = .recommended
        }

        return PurchaseWhatIfAnalysis(
            purchaseAssessment: purchase.assessment,
            purchaseExplanation: purchase.explanation,
            goalImpacts: impacts,
            safeToSpendBefore: before,
            safeToSpendAfter: after,
            runwayBefore: before.primary.runway,
            runwayAfter: conservativeAfter.runway,
            goalDateChanges: FinancialStateEngine.goalDateChanges(
                from: before.primary.goalProjections,
                to: conservativeAfter.goalProjections,
                calendar: calendar
            ),
            scenarioOutcomes: outcomes,
            limitingConstraint: conservativeAfter.limitingConstraint,
            dependsOnUncertainIncome: dependencies,
            recommendation: recommendation
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
