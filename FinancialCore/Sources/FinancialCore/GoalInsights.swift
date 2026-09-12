import Foundation

public struct GoalPlanAssessment: Sendable {
    public let goal: Goal
    public let status: FinancialHealthStatus
    public let effectiveDeadline: Date
    public let remainingAmount: Double
    public let includedInBaseline: Bool
    public let shortfallToHardFloor: Double
    public let shortfallToRecommendedFloor: Double
    public let tightestDate: Date
    public let recommendedDate: Date?
}

public extension FinancialInsights {
    /// Assesses one goal using the same liquidity rules as the rest of the engine.
    /// Mandatory goals already live in the baseline cash path; flexible goals are
    /// evaluated as What-If decisions so the UI can show trade-offs explicitly.
    static func assessGoalPlan(
        profile: FinancialProfile,
        goal: Goal,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> GoalPlanAssessment {
        let effectiveDeadline = max(goal.deadline, profile.asOfDate)

        switch goal.priority {
        case .mandatory:
            let horizon = try FinancialEngine.minimumHeadroom(
                profile: profile,
                from: profile.asOfDate,
                through: effectiveDeadline,
                calendar: calendar
            )
            let status = healthStatus(for: horizon)

            return GoalPlanAssessment(
                goal: goal,
                status: status,
                effectiveDeadline: effectiveDeadline,
                remainingAmount: goal.remainingAmount,
                includedInBaseline: true,
                shortfallToHardFloor: max(0, -horizon.minimumHardHeadroom),
                shortfallToRecommendedFloor: max(0, -horizon.minimumRecommendedHeadroom),
                tightestDate: status == .notSafe
                    ? horizon.tightestHardDate
                    : horizon.tightestRecommendedDate,
                recommendedDate: nil
            )

        case .flexible:
            let assessment = try FinancialEngine.assessFlexibleGoal(
                profile: profile,
                goal: goal,
                planningHorizon: max(planningHorizon, effectiveDeadline),
                calendar: calendar
            ).purchaseAssessment

            let status: FinancialHealthStatus
            switch assessment.status {
            case .safe:
                status = .safe
            case .tight:
                status = .tight
            case .notSafe:
                status = .notSafe
            }

            return GoalPlanAssessment(
                goal: goal,
                status: status,
                effectiveDeadline: effectiveDeadline,
                remainingAmount: goal.remainingAmount,
                includedInBaseline: false,
                shortfallToHardFloor: assessment.shortfallToHardFloor,
                shortfallToRecommendedFloor: assessment.shortfallToRecommendedFloor,
                tightestDate: assessment.status == .notSafe
                    ? assessment.tightestHardDate
                    : assessment.tightestRecommendedDate,
                recommendedDate: assessment.recommendedDate
            )
        }
    }

    static func assessAllGoals(
        profile: FinancialProfile,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> [GoalPlanAssessment] {
        try profile.goals
            .sorted { $0.deadline < $1.deadline }
            .map { goal in
                try assessGoalPlan(
                    profile: profile,
                    goal: goal,
                    planningHorizon: planningHorizon,
                    calendar: calendar
                )
            }
    }
}
