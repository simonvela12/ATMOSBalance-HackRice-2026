import Foundation

public enum FinancialWeatherState: String, Codable, CaseIterable, Sendable {
    case sunny
    case partlySunny
    case cloudy
    case rain
    case storm
}

public struct FinancialWeatherAssessment: Sendable {
    public let state: FinancialWeatherState
    public let score: Double
    public let liquidityScore: Double
    public let cashFlowScore: Double
    public let obligationScore: Double
    public let goalScore: Double
    public let minimumProjectedBalance: Double
    public let recommendedFloor: Double
    public let hasEnoughData: Bool
}

/// Produces weather from ratios relative to the user's own spending and obligations.
/// No dollar threshold is used, so the same balance can correctly mean different
/// things for people with different financial needs.
public enum FinancialWeatherEngine {
    public static func assess(
        profile: FinancialProfile,
        through endDate: Date? = nil,
        calendar: Calendar = .current
    ) throws -> FinancialWeatherAssessment {
        let periodEnd = max(
            endDate ?? calendar.date(byAdding: .day, value: 30, to: profile.asOfDate) ?? profile.asOfDate,
            profile.asOfDate
        )
        let weeklySamples = FinancialEngine.eligibleWeeklySpendingValues(profile: profile, calendar: calendar)
            .filter { $0 > 0.005 }
        let typicalMonthly = FinancialEngine.median(weeklySamples) * 52 / 12
        let income = FinancialEngine.expectedIncome(profile: profile, targetDate: periodEnd)
        let expenses = FinancialEngine.committedExpenses(profile: profile, targetDate: periodEnd)
        let mandatoryGoals = FinancialEngine.mandatoryGoalPayments(profile: profile, targetDate: periodEnd)
        let projectedVariable = FinancialEngine.projectedVariableSpending(profile: profile, targetDate: periodEnd, calendar: calendar)
        let baselineNeed = max(typicalMonthly, expenses + mandatoryGoals, projectedVariable)
        let activeGoals = profile.goals.filter { $0.lifecycleState == .active && !$0.isCompleted }
        let hasEnoughData = baselineNeed > 0.005 || !activeGoals.isEmpty || income > 0.005

        guard hasEnoughData else {
            return FinancialWeatherAssessment(
                state: .cloudy,
                score: 50,
                liquidityScore: 17.5,
                cashFlowScore: 12.5,
                obligationScore: 10,
                goalScore: 10,
                minimumProjectedBalance: profile.currentCash,
                recommendedFloor: FinancialEngine.hardFloor(profile: profile, on: profile.asOfDate),
                hasEnoughData: false
            )
        }

        let scale = max(baselineNeed, 1)
        var date = profile.asOfDate
        var minimumBalance = profile.currentCash
        var minimumRecommendedHeadroom = Double.greatestFiniteMagnitude
        while date <= periodEnd {
            let point = try FinancialEngine.forecast(profile: profile, targetDate: date, calendar: calendar)
            minimumBalance = min(minimumBalance, point.projectedCash)
            minimumRecommendedHeadroom = min(minimumRecommendedHeadroom, point.recommendedHeadroom)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        let floor = FinancialEngine.hardFloor(profile: profile, on: profile.asOfDate)
            + FinancialEngine.safetyBuffer(profile: profile, calendar: calendar)
        let liquidMonths = (minimumBalance - floor) / scale
        let liquidityScore = 35 * clamp(liquidMonths / 2)

        let netFlow = income - expenses - mandatoryGoals - projectedVariable
        let flowRatio = netFlow / scale
        let cashFlowScore = 25 * clamp((flowRatio + 0.5) / 1.0)

        let required = expenses + mandatoryGoals + projectedVariable
        let availableForRequirements = max(0, profile.currentCash - floor) + income
        let obligationScore = required > 0.005
            ? 20 * clamp(availableForRequirements / required)
            : 20

        let goalScore = try goalHealthScore(profile: profile, through: periodEnd, calendar: calendar)
        var score = liquidityScore + cashFlowScore + obligationScore + goalScore

        // A weak closing balance cannot conceal a dangerous dip earlier in the month.
        if minimumBalance < FinancialEngine.hardFloor(profile: profile, on: profile.asOfDate) {
            score = min(score, 24)
        } else if minimumRecommendedHeadroom < 0 {
            score = min(score, 44)
        }

        return FinancialWeatherAssessment(
            state: state(for: score),
            score: score,
            liquidityScore: liquidityScore,
            cashFlowScore: cashFlowScore,
            obligationScore: obligationScore,
            goalScore: goalScore,
            minimumProjectedBalance: minimumBalance,
            recommendedFloor: floor,
            hasEnoughData: true
        )
    }

    private static func goalHealthScore(
        profile: FinancialProfile,
        through endDate: Date,
        calendar: Calendar
    ) throws -> Double {
        let active = profile.goals.filter { $0.lifecycleState == .active && !$0.isCompleted }
        guard !active.isEmpty else { return 20 }
        let portfolio = try SmartGoalEngine.evaluate(profile: profile, planningHorizon: max(endDate, active.map(\.deadline).max() ?? endDate), calendar: calendar)
        var weightedTotal = 0.0
        var weights = 0.0
        for health in portfolio.goals where health.goal.lifecycleState == .active && !health.goal.isCompleted {
            let weight = max(0.75, health.goal.priority.weight)
            let value: Double
            switch health.status {
            case .ahead: value = 1
            case .onTrack: value = 0.85
            case .behind: value = 0.55
            case .atRisk: value = 0.3
            case .unrealistic: value = 0
            case .completed, .paused: continue
            }
            weightedTotal += value * weight
            weights += weight
        }
        return weights > 0 ? 20 * weightedTotal / weights : 20
    }

    private static func state(for score: Double) -> FinancialWeatherState {
        switch score {
        case 80...: return .sunny
        case 65..<80: return .partlySunny
        case 45..<65: return .cloudy
        case 25..<45: return .rain
        default: return .storm
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
